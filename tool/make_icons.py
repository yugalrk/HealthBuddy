#!/usr/bin/env python3
"""Generate app icons and the Play Store graphics.

The mark is a thali: one plate with katoris arranged around it, which reads as
"a balanced Indian meal" and stays legible down to 48px.

    python3 tool/make_icons.py
"""
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import math

ROOT = Path(__file__).resolve().parent.parent
ANDROID_RES = ROOT / "android/app/src/main/res"
STORE = ROOT / "store"

GREEN = (46, 125, 82)
GREEN_DARK = (31, 90, 58)
PLATE = (255, 253, 247)
DAL = (226, 160, 45)       # amber - dal
SABZI = (106, 168, 79)     # green - sabzi
CURD = (245, 238, 222)     # cream - curd
ROTI = (222, 184, 135)     # tan - roti


def draw_mark(size, bg=True, scale=1.0):
    """Draw the thali mark on a square canvas of `size` px."""
    ss = 4  # supersample for clean edges
    s = size * ss
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    if bg:
        d.rounded_rectangle([0, 0, s, s], radius=int(s * 0.22), fill=GREEN)

    cx = cy = s / 2
    plate_r = s * 0.33 * scale

    # plate
    d.ellipse([cx - plate_r, cy - plate_r, cx + plate_r, cy + plate_r],
              fill=PLATE)

    # rice mound in the centre
    inner_r = plate_r * 0.36
    d.ellipse([cx - inner_r, cy - inner_r, cx + inner_r, cy + inner_r],
              fill=(255, 255, 255), outline=(228, 222, 205),
              width=max(1, int(s * 0.004)))

    # katoris around the rim
    katori_r = plate_r * 0.235
    orbit = plate_r * 0.70
    colours = [DAL, SABZI, CURD, ROTI]
    for i, colour in enumerate(colours):
        ang = math.radians(-90 + i * 90 + 45)
        kx = cx + orbit * math.cos(ang)
        ky = cy + orbit * math.sin(ang)
        d.ellipse([kx - katori_r, ky - katori_r, kx + katori_r, ky + katori_r],
                  fill=colour, outline=(228, 222, 205),
                  width=max(1, int(s * 0.003)))

    return img.resize((size, size), Image.LANCZOS)


def write(img, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print(f"  {path.relative_to(ROOT)}  {img.size[0]}x{img.size[1]}")


def main():
    print("Launcher icons (legacy mipmaps):")
    for folder, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                       ("xxhdpi", 144), ("xxxhdpi", 192)]:
        write(draw_mark(px), ANDROID_RES / f"mipmap-{folder}/ic_launcher.png")

    print("Adaptive icon foreground (content inside the 66% safe zone):")
    for folder, px in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216),
                       ("xxhdpi", 324), ("xxxhdpi", 432)]:
        # No background layer, and the mark shrunk so nothing is clipped by
        # whatever mask the launcher applies.
        write(draw_mark(px, bg=False, scale=0.62),
              ANDROID_RES / f"mipmap-{folder}/ic_launcher_foreground.png")

    print("Play Store icon (512x512, no alpha):")
    store_icon = draw_mark(512).convert("RGB")
    write(store_icon, STORE / "play_icon_512.png")

    print("Feature graphic (1024x500):")
    fg = Image.new("RGB", (1024, 500), GREEN_DARK)
    d = ImageDraw.Draw(fg)
    for y in range(500):  # vertical gradient
        t = y / 500
        d.line([(0, y), (1024, y)], fill=(
            int(GREEN_DARK[0] + (GREEN[0] - GREEN_DARK[0]) * t),
            int(GREEN_DARK[1] + (GREEN[1] - GREEN_DARK[1]) * t),
            int(GREEN_DARK[2] + (GREEN[2] - GREEN_DARK[2]) * t)))
    mark = draw_mark(300, bg=False, scale=1.25)
    fg.paste(mark, (80, (500 - mark.size[1]) // 2), mark)

    def font(sz):
        for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
                  "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
            if Path(p).exists():
                return ImageFont.truetype(p, sz)
        return ImageFont.load_default()

    # Keep every line inside a right margin; Play may crop the edges.
    right_limit = 1024 - 48
    lines = [
        ("HealthBuddy", 60, (255, 255, 255)),
        ("A balanced week, planned for you", 27, (214, 235, 222)),
        ("Meal plan + one shopping list", 23, (186, 217, 198)),
    ]
    x = 430
    rendered = []
    for text, size, colour in lines:
        f = font(size)
        while x + d.textlength(text, font=f) > right_limit and size > 12:
            size -= 1
            f = font(size)
        rendered.append((text, f, colour,
                         d.textbbox((0, 0), text, font=f)[3]))

    gap = 14
    total = sum(h for *_, h in rendered) + gap * (len(rendered) - 1)
    y = (500 - total) / 2
    for text, f, colour, h in rendered:
        d.text((x, y), text, font=f, fill=colour)
        y += h + gap
    write(fg, STORE / "feature_graphic_1024x500.png")


if __name__ == "__main__":
    main()
