"""Draws assets/thumbnail.png, the Steam Workshop thumbnail (original artwork)."""
import math
import pathlib

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "thumbnail.png"
W = H = 1024
GOLD, LIGHT, DIM = (214, 172, 92), (236, 222, 190), (150, 122, 70)
SERIF = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def hexagon(cx, cy, r):
    return [(cx + r * math.cos(math.radians(60 * i + 30)), cy + r * math.sin(math.radians(60 * i + 30)))
            for i in range(6)]


img = Image.new("RGB", (W, H))
d = ImageDraw.Draw(img)
for y in range(H):
    t = y / H
    d.line([(0, y), (W, y)], fill=(int(12 + 14 * t), int(17 + 16 * t), int(27 + 22 * t)))

glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([212, 170, 812, 770], fill=(205, 163, 82, 60))
glow = glow.filter(ImageFilter.GaussianBlur(120))
img.paste(glow, (0, 0), glow)

lattice = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ld = ImageDraw.Draw(lattice)
r = 58
for row in range(int(H / (r * 1.5)) + 2):
    for col in range(int(W / (r * 1.732)) + 2):
        ld.polygon(hexagon(col * r * 1.732 + (r * 0.866 if row % 2 else 0), row * r * 1.5, r),
                   outline=(200, 160, 80, 22))
img.paste(lattice, (0, 0), lattice)

d = ImageDraw.Draw(img)
d.rounded_rectangle([28, 28, W - 29, H - 29], radius=46, outline=GOLD, width=10)
d.rounded_rectangle([50, 50, W - 51, H - 51], radius=34, outline=DIM, width=3)


def card(cx, cy, angle):
    c = Image.new("RGBA", (250, 350), (0, 0, 0, 0))
    cd = ImageDraw.Draw(c)
    cd.rounded_rectangle([0, 0, 249, 349], radius=22, fill=(24, 33, 48), outline=GOLD, width=7)
    cd.rounded_rectangle([18, 18, 231, 331], radius=14, outline=DIM, width=3)
    for k, rr in enumerate((70, 48, 26)):
        cd.polygon(hexagon(125, 175, rr), outline=DIM if k == 1 else GOLD, width=5)
    c = c.rotate(angle, resample=Image.BICUBIC, expand=True)
    img.paste(c, (int(cx - c.width / 2), int(cy - c.height / 2)), c)


card(380, 330, 14)
card(644, 330, -14)
card(512, 300, 0)

d = ImageDraw.Draw(img)


def centered(y, text, size, fill, path=SERIF):
    font = ImageFont.truetype(path, size)
    d.text(((W - d.textlength(text, font=font)) / 2, y), text, font=font, fill=fill)


centered(555, "RIFTBOUND", 112, LIGHT)
centered(690, "MOD  ·  TTS  ·  OGY", 58, GOLD)
d.line([(250, 782), (774, 782)], fill=DIM, width=3)
centered(806, "1v1  ·  2v2  ·  FFA 3  ·  FFA 4", 40, LIGHT, SANS)
centered(866, "Deck-code import  ·  Auto setup", 36, (190, 196, 206), SANS)

img.save(OUT, optimize=True)
print(OUT)
