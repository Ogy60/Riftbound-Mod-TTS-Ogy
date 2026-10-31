"""Generates playmat.png (original design) from the zone layout in Global.lua."""
from PIL import Image, ImageDraw, ImageFont
import math, re, sys

lua_path, out_path = sys.argv[1], sys.argv[2]
S = 80
X1, X2, Z1, Z2 = -23, 23, -8.5, 8.5
W, H = int((X2 - X1) * S), int((Z2 - Z1) * S)


def px(x, z):
    return ((x - X1) * S, (Z2 - z) * S)  # image top = edge toward the table centre


img = Image.new("RGB", (W, H))
d = ImageDraw.Draw(img)
for y in range(H):
    t = y / H
    d.line([(0, y), (W, y)], fill=(int(14 + 10 * t), int(19 + 12 * t), int(28 + 16 * t)))
lat = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ld = ImageDraw.Draw(lat)
r = 46
for row in range(int(H / (r * 1.5)) + 2):
    for col in range(int(W / (r * 1.732)) + 2):
        cx = col * r * 1.732 + (r * 0.866 if row % 2 else 0)
        cy = row * r * 1.5
        ld.polygon([(cx + r * math.cos(math.radians(60 * i + 30)), cy + r * math.sin(math.radians(60 * i + 30)))
                    for i in range(6)], outline=(200, 160, 80, 16))
img.paste(lat, (0, 0), lat)
d = ImageDraw.Draw(img)
gold, dim, text = (205, 163, 82), (120, 96, 52), (222, 206, 170)
F = lambda s: ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf", s)

src = open(lua_path).read()
zones = re.findall(r'(\w+)\s*=\s*\{\s*(-?[\d.]+),\s*(-?[\d.]+),\s*"([A-Z ]+)"(,\s*true)?\s*\}',
                   src[src.index("ZONES = {"):src.index("BASE_AREA")])


def area(name):
    m = re.search(name + r'\s*=\s*\{\s*x1\s*=\s*(-?[\d.]+),\s*x2\s*=\s*(-?[\d.]+),\s*z1\s*=\s*(-?[\d.]+),'
                  r'\s*z2\s*=\s*(-?[\d.]+),\s*label\s*=\s*"([^"]+)"', src)
    return [float(v) for v in m.groups()[:4]] + [m.group(5)]


CW, CH = 2.6 + 0.3, 3.7 + 0.3


def frame(x1, z1, x2, z2, label, size=26, inside=False):
    a, b = px(x1, z2), px(x2, z1)
    d.rounded_rectangle([a, b], radius=18, fill=(22, 30, 42), outline=gold, width=5)
    d.rounded_rectangle([a[0] + 10, a[1] + 10, b[0] - 10, b[1] - 10], radius=12, outline=dim, width=2)
    f = F(size)
    tw = d.textlength(label, font=f)
    d.text(((a[0] + b[0]) / 2 - tw / 2, a[1] + 18 if inside else b[1] + 6), label, font=f, fill=text)


for name, x, z, label, land in zones:
    x, z = float(x), float(z)
    w, h = (4.4, 3.1) if land else (CW, CH)
    if name == "dice":
        w, h = 2.8, 2.8
    frame(x - w / 2, z - h / 2, x + w / 2, z + h / 2, label)
bx1, bx2, bz1, bz2, bl = area("BASE_AREA")
frame(bx1, bz1, bx2, bz2, bl, size=44, inside=True)
rx1, rx2, rz1, rz2, rl = area("REVEAL_AREA")
frame(rx1, rz1, rx2, rz2, rl, size=30, inside=True)
px1, px2, pz1, pz2, pl = area("POOL_AREA")
frame(px1, pz1, px2, pz2, pl, size=26, inside=False)
m = re.search(r'POOL_SLOTS\s*=\s*\{\s*x0\s*=\s*(-?[\d.]+),\s*dx\s*=\s*(-?[\d.]+),\s*z\s*=\s*(-?[\d.]+),'
              r'\s*count\s*=\s*(\d+)', src)
x0, dx, zz, cnt = float(m.group(1)), float(m.group(2)), float(m.group(3)), int(m.group(4))
for i in range(cnt):
    cx = x0 + i * dx
    d.rounded_rectangle([px(cx - 1.25, zz + 1.75), px(cx + 1.25, zz - 1.75)], radius=10, outline=dim, width=2)
d.rounded_rectangle([6, 6, W - 7, H - 7], radius=30, outline=gold, width=8)
img = img.resize((W * 3 // 4, H * 3 // 4), Image.LANCZOS)
img.save(out_path, optimize=True)
print(img.size)
