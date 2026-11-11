"""Draws the mod icons into src/quality-calculator/graphics: a big "legendary" quality icon from the game
and under it a row of four circles (normal, uncommon, rare, epic) on a dark tile.
The icon is taken from the installed game (data/quality/graphics/icons/quality-legendary.png), so the game must be installed.
Run: python -X utf8 tools/make_icons.py"""
import pathlib
from PIL import Image, ImageDraw

OUT = pathlib.Path(__file__).resolve().parent.parent / "src" / "quality-calculator" / "graphics"
GAME = pathlib.Path(r"F:\SteamLibrary\steamapps\common\Factorio\data\quality\graphics\icons")
# quality colors from the game (normal, uncommon, rare, epic)
DOTS = [(200, 200, 200), (43, 165, 61), (25, 104, 178), (137, 0, 178)]


def draw(size, with_dots):
    scale = 4
    s = size * scale
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = s * 0.06
    d.rounded_rectangle([pad, pad, s - pad, s - pad], radius=s * 0.16, fill=(38, 38, 42, 255),
                        outline=(160, 160, 165, 255), width=max(1, int(s * 0.03)))
    hero = Image.open(GAME / "quality-legendary.png").convert("RGBA")
    box = hero.getbbox()
    if box:
        hero = hero.crop(box)
    target = int(s * (0.56 if with_dots else 0.68))
    ratio = target / max(hero.size)
    hero = hero.resize((max(1, int(hero.width * ratio)), max(1, int(hero.height * ratio))), Image.LANCZOS)
    cx = (s - hero.width) // 2
    cy = int(s * (0.14 if with_dots else (s - hero.height) / s / 2 * 1.0))
    if not with_dots:
        cy = (s - hero.height) // 2
    img.alpha_composite(hero, (cx, cy))
    if with_dots:
        r = s * 0.058
        gap = s * 0.045
        total = 4 * 2 * r + 3 * gap
        x = (s - total) / 2 + r
        y = s * 0.80
        for color in DOTS:
            d.ellipse([x - r - s * 0.012, y - r - s * 0.012, x + r + s * 0.012, y + r + s * 0.012], fill=(0, 0, 0, 255))
            d.ellipse([x - r, y - r, x + r, y + r], fill=color + (255,))
            x += 2 * r + gap
    return img.resize((size, size), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, size, dots in (("tool-64", 64, True), ("shortcut-56", 56, True), ("shortcut-24", 24, False)):
        draw(size, dots).save(OUT / f"{name}.png")
        print("saved", name)
    # enlarged preview for the eyes (not part of the mod)
    preview = Image.new("RGBA", (64 * 4 * 3 + 40, 64 * 4 + 20), (60, 60, 64, 255))
    for i, (size, dots) in enumerate(((64, True), (56, True), (24, False))):
        im = draw(size, dots).resize((size * 4, size * 4), Image.NEAREST)
        preview.alpha_composite(im, (10 + i * (64 * 4 + 10), 10))
    preview.save(OUT.parent.parent.parent / "dist" / "icon-preview.png") if (OUT.parent.parent.parent / "dist").exists() else None


if __name__ == "__main__":
    main()
