#!/usr/bin/env python3
"""
Generate launcher, splash, Play Store, and transparent MEDCAIN art.

Source: assets/branding/logo_source.jpg (full lockup on black).

Outputs (committed — regenerate, then re-run Flutter icon/splash generators):
  assets/branding/logo_full.png          — transparent full lockup (dark canvas)
  assets/branding/logo_full_light.png    — dark-ink lockup for light paper
  assets/branding/app_icon.png           — mark on black (launcher / dark badge)
  assets/branding/app_icon_light.png     — mark on light paper (light badge)
  assets/branding/app_icon_foreground.png
  assets/branding/app_icon_monochrome.png
  assets/branding/splash_logo.png        — white+blue M, letter-fit (in-app / pre-12 splash)
  assets/branding/splash_logo_light.png  — dark+blue M, letter-fit (in-app / pre-12 splash)
  assets/branding/splash_icon.png        — circle-safe M (Android 12 splash, dark)
  assets/branding/splash_icon_light.png  — circle-safe M (Android 12 splash, light)
  store/play/icon-512.png
  store/play/feature-graphic-1024x500.png
  website/public/img/icon-512.png
  website/public/img/app-icon.png
  website/public/img/mark.png
  website/public/img/mark-light.png
  website/public/img/logo-full.png
  website/public/img/logo-full-light.png
  website/public/img/og.png
  assets/illustrations/mascot_*.png

Requires Pillow (scripts/.venv).
"""

from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
BRANDING = ROOT / "assets" / "branding"
ILLUSTRATIONS = ROOT / "assets" / "illustrations"
PLAY = ROOT / "store" / "play"
WEB_IMG = ROOT / "website" / "public" / "img"

# AppTheme.splashCanvas / ComicColors — lockstep with lib/core/theme/.
SPLASH_CANVAS = (0x00, 0x00, 0x00, 255)
SPLASH_CANVAS_LIGHT = (0xF4, 0xF4, 0xF5, 255)  # ComicColors.light.paper
LIGHT_INK = (0x1A, 0x1A, 0x1E, 255)  # ComicColors.light.ink
# Brand blue (mid of the logo gradient) for chrome accents / feature graphic.
BRAND_BLUE = (0x00, 0x8F, 0xD6, 255)
WHITE = (255, 255, 255, 255)
BLACK = (0, 0, 0, 255)
TRANSPARENT = (0, 0, 0, 0)

APP_NAME = "MEDCAIN"
TAGLINE = "Drug of Choice for Exam Pain"

FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Black.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
]


def _font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def _glyph(
    text: str,
    *,
    fill: tuple[int, int, int, int],
    font_size: int,
) -> Image.Image:
    """Render [text] and crop to actual ink (font metrics lie)."""
    font = _font(font_size)
    canvas_w = max(font_size * 4, font_size * (len(text) + 2))
    canvas_h = font_size * 4
    img = Image.new("RGBA", (canvas_w, canvas_h), TRANSPARENT)
    draw = ImageDraw.Draw(img)
    draw.text(
        (canvas_w // 2, canvas_h // 2),
        text,
        font=font,
        fill=fill,
        anchor="mm",
    )
    ink = img.getbbox()
    if ink is None:
        raise RuntimeError(f"font produced no ink for {text!r}")
    return img.crop(ink)


def _dist(a: tuple[int, ...], b: tuple[int, ...]) -> float:
    return (
        (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2
    ) ** 0.5


def _luma(rgb: tuple[int, ...]) -> float:
    return (rgb[0] + rgb[1] + rgb[2]) / 3.0


def knockout_black_background(
    src: Image.Image,
    *,
    black_luma: float = 28,
) -> Image.Image:
    """Punch near-black field to alpha; keep white + cyan/blue ink."""
    img = src.convert("RGBA")
    w, h = img.size
    pix = img.load()
    out = Image.new("RGBA", (w, h), TRANSPARENT)
    dest = out.load()

    for y in range(h):
        for x in range(w):
            r, g, b, _a = pix[x, y]
            L = _luma((r, g, b))
            if L < black_luma:
                # Soft edge: almost-black anti-alias → partial alpha.
                if L < black_luma * 0.45:
                    continue
                alpha = int(255 * (L - black_luma * 0.45) / (black_luma * 0.55))
                dest[x, y] = (r, g, b, max(0, min(255, alpha)))
                continue
            dest[x, y] = (r, g, b, 255)

    # Slight expand + blur so the knockout doesn't leave a hard fringe.
    alpha = out.getchannel("A").filter(ImageFilter.MaxFilter(3))
    alpha = alpha.filter(ImageFilter.GaussianBlur(radius=0.55))
    out.putalpha(alpha)
    return out


def crop_ink(img: Image.Image, *, pad_ratio: float = 0.04) -> Image.Image:
    box = img.getbbox()
    if box is None:
        raise RuntimeError("image has no ink after knockout")
    pad = max(4, round(min(img.size) * pad_ratio))
    left = max(0, box[0] - pad)
    top = max(0, box[1] - pad)
    right = min(img.size[0], box[2] + pad)
    bottom = min(img.size[1], box[3] + pad)
    return img.crop((left, top, right, bottom))


def extract_mark(full: Image.Image) -> Image.Image:
    """Top band of the lockup is the stylized M (+ ECG)."""
    w, h = full.size
    # Source layout (1024²): M ~172–584. Use relative cut so resizes stay safe.
    top = int(h * 0.14)
    bottom = int(h * 0.60)
    band = full.crop((0, top, w, bottom))
    return crop_ink(band, pad_ratio=0.06)


def _is_brand_blue(r: int, g: int, b: int) -> bool:
    """Cyan / brand-blue ECG and M peak — keep these on light canvases."""
    return b >= 120 and b > r + 15 and g >= r - 25


def for_light_canvas(src: Image.Image) -> Image.Image:
    """Near-white glyph → dark ink; preserve cyan/blue ECG for light paper."""
    img = src.convert("RGBA")
    pix = img.load()
    w, h = img.size
    out = Image.new("RGBA", (w, h), TRANSPARENT)
    dest = out.load()
    ir, ig, ib, _ = LIGHT_INK

    for y in range(h):
        for x in range(w):
            r, g, b, a = pix[x, y]
            if a == 0:
                continue
            if _is_brand_blue(r, g, b):
                dest[x, y] = (r, g, b, a)
                continue
            L = _luma((r, g, b))
            if L < 40:
                # Already dark fringe — keep, or drop if nearly black.
                dest[x, y] = (ir, ig, ib, a) if L >= 12 else (r, g, b, a)
                continue
            # White / gray anti-alias → ink; alpha follows how solid the source was.
            strength = min(1.0, max(0.0, (L - 40) / 180.0))
            na = int(a * (0.35 + 0.65 * strength))
            dest[x, y] = (ir, ig, ib, max(0, min(255, na)))
    return out


def _m_body_box(mark: Image.Image) -> tuple[int, int, int, int]:
    """Box around the tall M, ignoring the short ECG tails.

    The tails make the ink about twice as wide as it is tall, so fitting the
    full mark into a square shrinks the letter. Columns as tall as the legs
    bracket the M; the center peak sits between them.
    """
    img = mark.convert("RGBA")
    w, h = img.size
    pix = img.load()
    spans: list[tuple[int, int, int] | None] = [None] * w
    max_span = 0
    for x in range(w):
        ys = [y for y in range(h) if pix[x, y][3] > 32]
        if len(ys) < 8:
            continue
        span = ys[-1] - ys[0] + 1
        spans[x] = (ys[0], ys[-1], span)
        if span > max_span:
            max_span = span
    full = img.getbbox()
    if full is None:
        raise RuntimeError("mark has no ink")
    if max_span < 8:
        return full
    cutoff = max_span * 0.55
    xs = [x for x, span in enumerate(spans) if span is not None and span[2] >= cutoff]
    if len(xs) < 4:
        return full
    left, right = xs[0], xs[-1]
    top = min(spans[x][0] for x in xs)  # type: ignore[index]
    bottom = max(spans[x][1] for x in xs)  # type: ignore[index]
    return (left, top, right + 1, bottom + 1)


def _fit_mark(
    mark: Image.Image,
    size: int,
    *,
    occupy: float,
    background: tuple[int, int, int, int],
    monochrome: tuple[int, int, int, int] | None = None,
    fit_letter: bool = False,
) -> Image.Image:
    cropped = mark.getbbox()
    if cropped is None:
        raise RuntimeError("mark has no ink")
    glyph = mark.crop(cropped)
    if fit_letter:
        body = _m_body_box(glyph)
        bw = max(1, body[2] - body[0])
        bh = max(1, body[3] - body[1])
        target = int(size * occupy)
        ratio = target / max(bw, bh)
        anchor = (
            (body[0] + body[2]) / 2 * ratio,
            (body[1] + body[3]) / 2 * ratio,
        )
    else:
        gw, gh = glyph.size
        target = int(size * occupy)
        ratio = target / max(gw, gh)
        anchor = None
    glyph = glyph.resize(
        (max(1, round(glyph.size[0] * ratio)), max(1, round(glyph.size[1] * ratio))),
        Image.Resampling.LANCZOS,
    )
    if monochrome is not None:
        tinted = Image.new("RGBA", glyph.size, monochrome)
        tinted.putalpha(glyph.split()[-1])
        glyph = tinted
    if anchor is None:
        x = (size - glyph.size[0]) // 2
        y = (size - glyph.size[1]) // 2
    else:
        # Center the M. ECG tails may run off the canvas — that is intentional.
        x = round(size / 2 - anchor[0])
        y = round(size / 2 - anchor[1])
    out = Image.new("RGBA", (size, size), background)
    sx, sy = max(0, -x), max(0, -y)
    dx, dy = max(0, x), max(0, y)
    gw, gh = glyph.size
    piece = glyph.crop(
        (
            sx,
            sy,
            min(gw, sx + size - dx),
            min(gh, sy + size - dy),
        )
    )
    out.alpha_composite(piece, (dx, dy))
    return out


def _fit_lockup(
    lockup: Image.Image,
    *,
    max_w: int,
    max_h: int,
    background: tuple[int, int, int, int],
) -> Image.Image:
    cropped = lockup.getbbox()
    if cropped is None:
        raise RuntimeError("lockup has no ink")
    glyph = lockup.crop(cropped)
    gw, gh = glyph.size
    ratio = min(max_w / gw, max_h / gh)
    glyph = glyph.resize(
        (max(1, round(gw * ratio)), max(1, round(gh * ratio))),
        Image.Resampling.LANCZOS,
    )
    out = Image.new("RGBA", (max_w, max_h), background)
    x = (max_w - glyph.size[0]) // 2
    y = (max_h - glyph.size[1]) // 2
    out.alpha_composite(glyph, (x, y))
    return out


def _save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG")
    print(f"wrote {path.relative_to(ROOT)}")


def _feature_graphic(mark: Image.Image) -> Image.Image:
    width, height = 1024, 500
    img = Image.new("RGBA", (width, height), SPLASH_CANVAS)
    badge = _fit_mark(
        mark, 280, occupy=0.78, background=TRANSPARENT, fit_letter=True
    )
    img.alpha_composite(badge, (48, (height - 280) // 2))

    title = _glyph(APP_NAME, fill=WHITE, font_size=84)
    sub = _glyph(TAGLINE, fill=BRAND_BLUE, font_size=26)
    text_left = 360
    block_h = title.size[1] + 18 + sub.size[1]
    title_y = (height - block_h) // 2
    img.alpha_composite(title, (text_left, title_y))
    img.alpha_composite(sub, (text_left, title_y + title.size[1] + 18))
    return img


def _og_image(lockup: Image.Image) -> Image.Image:
    """1200×630 Open Graph card — lockup centered on black."""
    return _fit_lockup(
        lockup, max_w=1200, max_h=630, background=SPLASH_CANVAS
    ).convert("RGB")


def _is_warm_paper(rgb: tuple[int, ...]) -> bool:
    r, g, b = rgb[:3]
    mx, mn = max(r, g, b), min(r, g, b)
    return mx >= 218 and (mx - mn) <= 42 and b <= r + 8


def knockout_paper_background(src: Image.Image, max_dist: float = 18) -> Image.Image:
    """Flood-fill cream paper from the border. Keeps white coats inside ink."""
    img = src.convert("RGBA")
    w, h = img.size
    pix = img.load()
    seen = [[False] * w for _ in range(h)]
    queue: deque[tuple[int, int, tuple[int, int, int]]] = deque()

    def seed(x: int, y: int) -> None:
        p = pix[x, y]
        if seen[y][x] or not _is_warm_paper(p):
            return
        seen[y][x] = True
        queue.append((x, y, (p[0], p[1], p[2])))

    for x in range(w):
        seed(x, 0)
        seed(x, h - 1)
    for y in range(h):
        seed(0, y)
        seed(w - 1, y)

    background: list[tuple[int, int]] = []
    while queue:
        x, y, sample = queue.popleft()
        background.append((x, y))
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if nx < 0 or ny < 0 or nx >= w or ny >= h or seen[ny][nx]:
                continue
            p = pix[nx, ny]
            # Thick comic ink is a hard wall — never punch through it.
            if p[0] < 72 and p[1] < 72 and p[2] < 72:
                seen[ny][nx] = True
                continue
            if _dist(p, sample) <= max_dist and _is_warm_paper(p):
                seen[ny][nx] = True
                queue.append((nx, ny, sample))

    for x, y in background:
        pix[x, y] = TRANSPARENT

    alpha = img.getchannel("A").filter(ImageFilter.MaxFilter(3))
    alpha = alpha.filter(ImageFilter.GaussianBlur(radius=0.7))
    img.putalpha(alpha)
    box = img.getbbox()
    if box is None:
        return img
    pad = max(4, round(min(img.size) * 0.04))
    left = max(0, box[0] - pad)
    top = max(0, box[1] - pad)
    right = min(img.size[0], box[2] + pad)
    bottom = min(img.size[1], box[3] + pad)
    return img.crop((left, top, right, bottom))


def process_mascots() -> None:
    mapping = {
        "mascot_wave.jpg": "mascot_wave.png",
        "mascot_study.jpg": "mascot_study.png",
        "mascot_avatar.jpg": "mascot_avatar.png",
    }
    for src_name, dest_name in mapping.items():
        src = ILLUSTRATIONS / src_name
        if not src.exists():
            print(f"skip {src_name} (missing)")
            continue
        knocked = knockout_paper_background(Image.open(src))
        _save(knocked, ILLUSTRATIONS / dest_name)


def load_lockup() -> Image.Image:
    source_path = BRANDING / "logo_source.jpg"
    if not source_path.exists():
        # Back-compat: older teal mark source.
        legacy = BRANDING / "app_icon_source.png"
        if legacy.exists():
            print(f"no logo_source.jpg — falling back to {legacy.name}")
            return Image.open(legacy).convert("RGBA")
        raise FileNotFoundError(
            f"Missing {source_path.relative_to(ROOT)} — drop the MEDCAIN logo JPG there."
        )
    print(f"processing {source_path.relative_to(ROOT)}")
    return knockout_black_background(Image.open(source_path))


def main() -> None:
    BRANDING.mkdir(parents=True, exist_ok=True)
    PLAY.mkdir(parents=True, exist_ok=True)
    WEB_IMG.mkdir(parents=True, exist_ok=True)

    lockup = load_lockup()
    full = crop_ink(lockup, pad_ratio=0.03)
    _save(full, BRANDING / "logo_full.png")
    _save(full, WEB_IMG / "logo-full.png")

    mark = extract_mark(lockup)
    mark_light = for_light_canvas(mark)
    full_light = for_light_canvas(full)

    # Square badges / in-app splash: size to the M so the letter fills the tile.
    # ECG tails are allowed to leave the canvas. 0.74 keeps the pulse bumps.
    icon = _fit_mark(
        mark, 1024, occupy=0.74, background=SPLASH_CANVAS, fit_letter=True
    )
    _save(icon.convert("RGB"), BRANDING / "app_icon.png")

    # Light-theme wordmark badge: dark ink + blue ECG on paper field.
    icon_light = _fit_mark(
        mark_light,
        1024,
        occupy=0.74,
        background=SPLASH_CANVAS_LIGHT,
        fit_letter=True,
    )
    _save(icon_light.convert("RGB"), BRANDING / "app_icon_light.png")

    splash = _fit_mark(
        mark, 1024, occupy=0.74, background=TRANSPARENT, fit_letter=True
    )
    _save(splash, BRANDING / "splash_logo.png")

    splash_light = _fit_mark(
        mark_light, 1024, occupy=0.74, background=TRANSPARENT, fit_letter=True
    )
    _save(splash_light, BRANDING / "splash_logo_light.png")

    # Circle-masked surfaces (adaptive icon, Android 12 splash). The visible
    # disc is the center ~67% of the layer, so a smaller occupy keeps the
    # M legs inside the mask. Launcher inset is 0 — padding lives here.
    foreground = _fit_mark(
        mark, 1024, occupy=0.54, background=TRANSPARENT, fit_letter=True
    )
    _save(foreground, BRANDING / "app_icon_foreground.png")
    _save(foreground, BRANDING / "splash_icon.png")

    splash_icon_light = _fit_mark(
        mark_light, 1024, occupy=0.54, background=TRANSPARENT, fit_letter=True
    )
    _save(splash_icon_light, BRANDING / "splash_icon_light.png")

    _save(full_light, BRANDING / "logo_full_light.png")
    _save(full_light, WEB_IMG / "logo-full-light.png")

    monochrome = _fit_mark(
        mark,
        1024,
        occupy=0.54,
        background=TRANSPARENT,
        monochrome=BLACK,
        fit_letter=True,
    )
    _save(monochrome, BRANDING / "app_icon_monochrome.png")

    store_icon = icon.resize((512, 512), Image.Resampling.LANCZOS).convert("RGB")
    _save(store_icon, PLAY / "icon-512.png")
    _save(store_icon, WEB_IMG / "icon-512.png")
    _save(store_icon, WEB_IMG / "app-icon.png")
    # Transparent mark for dark hero / overlays (not light nav — white ink vanishes).
    mark_badge = _fit_mark(
        mark, 512, occupy=0.80, background=TRANSPARENT, fit_letter=True
    )
    _save(mark_badge, WEB_IMG / "mark.png")
    mark_badge_light = _fit_mark(
        mark_light, 512, occupy=0.80, background=TRANSPARENT, fit_letter=True
    )
    _save(mark_badge_light, WEB_IMG / "mark-light.png")
    _save(_feature_graphic(mark).convert("RGB"), PLAY / "feature-graphic-1024x500.png")
    _save(_og_image(full), WEB_IMG / "og.png")

    process_mascots()


if __name__ == "__main__":
    main()
