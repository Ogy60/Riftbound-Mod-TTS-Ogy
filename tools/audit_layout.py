"""Audits the table geometry in Global.lua for every mode: zones inside mats,
no overlaps between zones, mats, battlefields, control strips, host console,
token trays; and that every zone is used by some function."""
import re, sys, itertools

src = open(sys.argv[1]).read()


def num(pat):
    return float(re.search(pat, src).group(1))


ZONES = {m[0]: (float(m[1]), float(m[2]), bool(m[4])) for m in re.findall(
    r'(\w+)\s*=\s*\{\s*(-?[\d.]+),\s*(-?[\d.]+),\s*"([A-Z ]+)"(,\s*true)?\s*\}',
    src[src.index("ZONES = {"):src.index("BASE_AREA")])}
AREAS = {}
for name in ("BASE_AREA", "POOL_AREA", "REVEAL_AREA"):
    m = re.search(name + r'\s*=\s*\{\s*x1\s*=\s*(-?[\d.]+),\s*x2\s*=\s*(-?[\d.]+),\s*z1\s*=\s*(-?[\d.]+),\s*z2\s*=\s*(-?[\d.]+)', src)
    AREAS[name] = tuple(float(v) for v in m.groups())
CW, CH = 2.6 + 0.3, 3.7 + 0.3
MAT_W, MAT_D = 46, 17
LAYOUT = {}
for key in ("Duel", "Four"):
    m = re.search(key + r'\s*=\s*\{\s*tableW\s*=\s*([\d.]+),\s*tableD\s*=\s*([\d.]+),\s*matZ\s*=\s*(-?[\d.]+),'
                        r'\s*consoleZ\s*=\s*(-?[\d.]+),\s*handZ\s*=\s*(-?[\d.]+)', src)
    LAYOUT[key] = [float(v) for v in m.groups()]
SIDES = {"S": ((1, 0), (0, 1)), "N": ((-1, 0), (0, -1)), "W": ((0, -1), (1, 0)), "E": ((0, 1), (-1, 0))}
SEAT_SIDE = {"Duel": {"Red": "S", "Blue": "N"}, "Four": {"Red": "S", "Blue": "W", "Yellow": "N", "Green": "E"}}
MODES = {"1v1": ("Duel", ["Red", "Blue"]), "2v2": ("Four", ["Red", "Blue", "Yellow", "Green"]),
         "FFA 3": ("Four", ["Red", "Blue", "Green"]), "FFA 4": ("Four", ["Red", "Blue", "Yellow", "Green"])}
ctrl = re.findall(r'\{\s*"(\w+)",\s*(-?[\d.]+),\s*(-?1),\s*([\d.]+),', src[src.index("SEAT_CONTROLS = {"):src.index("ROW_DZ")])
POOL = re.search(r'POOL_SLOTS\s*=\s*\{\s*x0\s*=\s*(-?[\d.]+),\s*dx\s*=\s*(-?[\d.]+),\s*z\s*=\s*(-?[\d.]+),\s*count\s*=\s*(\d+)', src)
x0, dx, pz, pc = float(POOL.group(1)), float(POOL.group(2)), float(POOL.group(3)), int(POOL.group(4))

problems = []


def overlap(a, b, eps=0.05):
    return a[0] < b[2] - eps and b[0] < a[2] - eps and a[1] < b[3] - eps and b[1] < a[3] - eps


# --- 1. zones inside the mat and not overlapping each other (mat coordinates)
rects = {}
for k, (u, v, land) in ZONES.items():
    w, h = (4.4, 3.1) if land else (CW, CH)
    if k == "dice":
        w, h = 2.8, 2.8
    rects[k] = (u - w / 2, v - h / 2, u + w / 2, v + h / 2)
for k, a in AREAS.items():
    rects[k] = (a[0], a[2], a[1], a[3])
rects["drop bottom main"] = (12.6 - 1.45, 0.1 - 0.75, 12.6 + 1.45, 0.1 + 0.75)
rects["drop bottom rune"] = (-19.5 - 1.45, 0.1 - 0.75, -19.5 + 1.45, 0.1 + 0.75)
rects["action bar"] = (-11.4 - 1.8, 0.1 - 0.55, -11.4 + 5 * 3.9 + 1.8, 0.1 + 0.55)
for i in range(pc):
    u = x0 + i * dx
    r = (u - 1.3, pz - 1.85, u + 1.3, pz + 1.85)
    if not (r[0] >= AREAS["POOL_AREA"][0] and r[2] <= AREAS["POOL_AREA"][1]):
        problems.append(f"rune pool slot {i + 1} sticks out of the pool area")
for k, r in rects.items():
    if r[0] < -MAT_W / 2 or r[2] > MAT_W / 2 or r[1] < -MAT_D / 2 or r[3] > MAT_D / 2:
        problems.append(f"zone {k} is outside the mat")
for (ka, a), (kb, b) in itertools.combinations(rects.items(), 2):
    if overlap(a, b):
        problems.append(f"zones {ka} and {kb} overlap")
print(f"Mat: {len(rects)} zones + {pc} rune slots checked")


# --- 2. per mode: world rectangles of everything big
def world_rect(side, u1, z1, u2, z2):
    r, f = SIDES[side]
    pts = [(r[0] * u + f[0] * z, r[1] * u + f[1] * z) for u in (u1, u2) for z in (z1, z2)]
    xs, zs = [p[0] for p in pts], [p[1] for p in pts]
    return (min(xs), min(zs), max(xs), max(zs))


for mode, (key, seats) in MODES.items():
    tw, td, matZ, conZ, handZ = LAYOUT[key]
    objs = {}
    for c in seats:
        s = SEAT_SIDE[key][c]
        objs[f"{c} mat"] = world_rect(s, -MAT_W / 2, matZ - MAT_D / 2, MAT_W / 2, matZ + MAT_D / 2)
        objs[f"{c} controls"] = world_rect(s, -23.2, conZ - 1.85, 23.2, conZ + 1.85)
        for k, u, row, w in ctrl:
            u, row, w = float(u), int(row), float(w)
            if u - w / 2 < -23.2 or u + w / 2 > 23.2:
                problems.append(f"{mode}: control {k} sticks out of {c}'s strip")
    slots = [-9, 9] if key == "Duel" else [-14, 0, 14]
    for i, x in enumerate(slots):
        objs[f"battlefield {i + 1}"] = (x - 6.25, -6.3, x + 6.25, 6.3)
    hx, hz = (31, 0) if key == "Duel" else (34.5, -34.5)
    objs["host console"] = (hx - 5.8, hz - 8.7, hx + 5.8, hz + 6.0)
    if key == "Duel":
        objs["marker supply W"] = (-30.5 - 4.3, -9 - 3.4, -30.5 + 4.3, -9 + 4.4)
        objs["marker supply E"] = (30.5 - 4.3, 13 - 4.4, 30.5 + 4.3, 13 + 3.4)
        objs["token selector"] = (-30.5 - 4.5, 11 - 3.5, -30.5 + 4.5, 11 + 3.5)
    else:
        objs["marker supply SW"] = (-34.5 - 4.3, -34.5 - 3.4, -34.5 + 4.3, -34.5 + 4.4)
        objs["marker supply NE"] = (34.5 - 4.3, 34.5 - 3.4, 34.5 + 4.3, 34.5 + 4.4)
        objs["token selector NW"] = (-34.5 - 4.5, 34.5 - 3.5, -34.5 + 4.5, 34.5 + 3.5)
    for k, r in objs.items():
        if r[0] < -tw / 2 or r[2] > tw / 2 or r[1] < -td / 2 or r[3] > td / 2:
            problems.append(f"{mode}: {k} is off the table")
    for (ka, a), (kb, b) in itertools.combinations(objs.items(), 2):
        if overlap(a, b):
            problems.append(f"{mode}: {ka} overlaps {kb}")
    print(f"{mode}: {len(objs)} table elements checked")

# --- 3. every zone is used somewhere
uses = {k: len(re.findall(r'zonePos\(\s*\w+,\s*"' + k + '"', src)) + len(re.findall(r'"' + k + r'"\)', src)) +
        len(re.findall(r'ZONES\.' + k, src)) for k in ZONES}
for k, n in uses.items():
    print(f"  zone {k:10s} referenced {n}x")
    if n == 0:
        problems.append(f"zone {k} is never used by any function")
for a in AREAS:
    n = len(re.findall(a, src)) - 1
    print(f"  area {a:12s} referenced {n}x")

print("\nPROBLEMS:" if problems else "\nNo problems found.")
for p in problems:
    print(" -", p)
