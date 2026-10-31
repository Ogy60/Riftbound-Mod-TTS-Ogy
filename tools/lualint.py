"""Tiny Lua structural linter: strips comments/strings, then checks block
keyword balance (function/if/for/while/do/repeat vs end/until), bracket
balance, and that every `if`/`elseif` has a `then` and every for/while a `do`.
Also flags Lua 5.3+ syntax that TTS (MoonSharp, Lua 5.2) rejects."""
import re, sys

src = open(sys.argv[1], encoding="utf-8").read()

def strip(s):
    out, i, n, line = [], 0, len(s), 1
    while i < n:
        c = s[i]
        if s.startswith("--", i):
            m = re.match(r"--\[(=*)\[", s[i:])
            if m:
                close = "]" + m.group(1) + "]"
                j = s.find(close, i)
                if j < 0: sys.exit(f"unterminated long comment line {line}")
                out.append("\n" * s[i:j].count("\n")); i = j + len(close); continue
            j = s.find("\n", i); i = n if j < 0 else j; continue
        m = re.match(r"\[(=*)\[", s[i:])
        if m:
            close = "]" + m.group(1) + "]"
            j = s.find(close, i)
            if j < 0: sys.exit("unterminated long string")
            out.append(' "" ' + "\n" * s[i:j].count("\n")); i = j + len(close); continue
        if c in "\"'":
            j = i + 1
            while j < n and s[j] != c:
                if s[j] == "\\": j += 1
                if s[j] == "\n": sys.exit(f"newline in string near line {s[:i].count(chr(10))+1}")
                j += 1
            out.append(' "" '); i = j + 1; continue
        out.append(c); i += 1
    return "".join(out)

code = strip(src)
errors = []
stack = []
pending = []  # 'for'/'while' waiting for 'do', 'if'/'elseif' waiting for 'then'
brackets = []
pairs_ = {")": "(", "]": "[", "}": "{"}
for lineno, line in enumerate(code.split("\n"), 1):
    if re.search(r"(?<![-])//|[^~=<>]=?\s*&\s*|\s>>\s|\s<<\s|\bgoto\b", line):
        if re.search(r"//|\s>>\s|\s<<\s", line):
            errors.append(f"{lineno}: Lua 5.3 operator")
    for tok in re.findall(r"[A-Za-z_][A-Za-z0-9_]*|[()\[\]{}]", line):
        if tok in "([{":
            brackets.append((tok, lineno))
        elif tok in ")]}":
            if not brackets or brackets[-1][0] != pairs_[tok]:
                errors.append(f"{lineno}: unmatched {tok}")
            else:
                brackets.pop()
        elif tok in ("function", "if", "repeat"):
            stack.append((tok, lineno))
            if tok == "if": pending.append(("then", lineno))
        elif tok in ("for", "while"):
            stack.append((tok, lineno)); pending.append(("do", lineno))
        elif tok == "elseif":
            pending.append(("then", lineno))
        elif tok == "then":
            if not pending or pending[-1][0] != "then": errors.append(f"{lineno}: stray then")
            else: pending.pop()
        elif tok == "do":
            if pending and pending[-1][0] == "do": pending.pop()
            else: stack.append(("do", lineno))
        elif tok == "end":
            if not stack or stack[-1][0] == "repeat": errors.append(f"{lineno}: stray end")
            else: stack.pop()
        elif tok == "until":
            if not stack or stack[-1][0] != "repeat": errors.append(f"{lineno}: stray until")
            else: stack.pop()
for t, l in stack: errors.append(f"unclosed {t} from line {l}")
for t, l in pending: errors.append(f"missing {t} for line {l}")
for t, l in brackets: errors.append(f"unclosed {t} from line {l}")
print("\n".join(errors) if errors else f"OK: {src.count(chr(10))} lines, blocks and brackets balanced")
