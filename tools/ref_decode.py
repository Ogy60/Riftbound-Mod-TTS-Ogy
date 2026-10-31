"""Python mirror of the Lua decoder (same structure, line-for-line), used to
validate the algorithm against Piltover Archive's golden fixtures since no Lua
interpreter is available in this sandbox."""
import json, sys

ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
SETS = {0: "OGN", 1: "OGS", 2: "ARC", 3: "SFD", 4: "UNL", 5: "VEN", 6: "RAD"}
VARIANTS = {0: "", 1: "a", 2: "s", 3: "b"}


def b32decode(s):
    out, buf, bits = [], 0, 0
    for ch in s:
        if ch in " \t\r\n=":
            continue
        v = ALPHA.find(ch.upper())
        if v < 0:
            raise ValueError("bad char " + ch)
        buf = buf * 32 + v          # Lua: no bit ops, keep arithmetic
        bits += 5
        if bits >= 8:
            bits -= 8
            p = 2 ** bits
            out.append((buf // p) % 256)
            buf = buf % p
    return out


class R:
    def __init__(s, b): s.b, s.i = b, 0
    def byte(s):
        if s.i >= len(s.b): raise ValueError("eof")
        v = s.b[s.i]; s.i += 1; return v
    def var(s):
        res, mul = 0, 1
        while True:
            v = s.byte()
            res += (v % 128) * mul
            if v < 128: return res
            mul *= 128


def pad(n, w):
    return str(n).rjust(w, "0")


def num_with_flag(r, flagged):
    if not flagged:
        return pad(r.var(), 3)
    f = r.byte(); n = r.var()
    if f == 0: return pad(n, 3)
    if f == 1: return "R" + pad(n, 2)
    if f == 2: return "SP" + str(n)
    raise ValueError("flag")


def group(r, count, flagged, deck):
    n = r.var(); st = r.byte(); va = r.byte()
    sc = SETS[st]; vc = VARIANTS[va]
    for _ in range(n):
        deck.append({"cardCode": f"{sc}-{num_with_flag(r, flagged)}{vc}", "count": count})


def section_fixed(r, maxc, flagged):
    d = []
    for c in range(maxc, 0, -1):
        for _ in range(r.var()):
            group(r, c, flagged, d)
    return d


def section_sparse(r, flagged):
    d = []
    for _ in range(r.var()):
        c = r.var()
        for _ in range(r.var()):
            group(r, c, flagged, d)
    return d


def cardref(r, flagged):
    st = r.byte(); va = r.byte()
    return f"{SETS[st]}-{num_with_flag(r, flagged)}{VARIANTS[va]}"


def decode(code):
    r = R(b32decode(code))
    fv = r.byte(); fmt = fv // 16; ver = fv % 16
    assert fmt == 1 and 1 <= ver <= 6
    if ver >= 5:
        flagged = r.byte() == 1
        main = section_sparse(r, flagged); side = section_sparse(r, flagged)
    else:
        flagged = ver >= 4
        main = section_fixed(r, 12, flagged)
        side = section_fixed(r, 3, flagged) if ver >= 2 else []
    out = {"mainDeck": main, "sideboard": side}
    if ver >= 3 and r.byte() == 1:
        out["chosenChampion"] = cardref(r, flagged)
    if ver >= 6:
        out["additionalLegends"] = [cardref(r, flagged) for _ in range(r.var())]
    return out


if __name__ == "__main__":
    ok = 0
    for f in sys.argv[1:]:
        for case in json.load(open(f)):
            got = decode(case["code"])
            exp = case["decoded"]
            same = all(got.get(k) == exp.get(k) for k in set(exp) | set(got)
                       if exp.get(k) is not None or got.get(k) is not None)
            print(("PASS " if same else "FAIL ") + case["name"])
            if not same:
                print(" exp", exp); print(" got", got)
            ok += same
    kai = "CIAAAAAAAAAQCAAAA4AACAIAABMQAAILAAAAICIMDMOVOX3AM5UHIAIDAAACO6XYAEAQKAAABX3QDGACUABKIAQAAEBQAAAWDBOQCAQAABMHE"
    print("README example:", json.dumps(decode(kai))[:300])
