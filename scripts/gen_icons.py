"""Generate freepdf app icons (PIL-based, no SVG parser needed).

Produces:
  app_icon_512.png     512x512  RGB  (no alpha, AGC requirement)
  app_icon_216.png     216x216  RGB
  startIcon.png       1024x1024 RGBA (fully opaque, launch icon)
  icon_background.png 1024x1024 RGB  (adaptive bg layer, opaque)
  icon_foreground.png 1024x1024 RGBA (adaptive fg layer, transparent bg)

Design (matches entry/src/main/resources/base/media/startIcon.svg):
  gradient #5B8CFF -> #9B5BFF diagonal, white doc card (92% opacity),
  two full bars (#5B8CFF, #9B5BFF) and one short bar.
"""

from PIL import Image, ImageDraw, ImageFont

OUT_DIR = r"D:\freepdf\entry\src\main\resources\base\media"

C1 = (0x5B, 0x8C, 0xFF)
C2 = (0x9B, 0x5B, 0xFF)
WHITE = (255, 255, 255)

SS = 4


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size):
    img = Image.new("RGB", (size, size))
    px = img.load()
    denom = 2 * (size - 1)
    for y in range(size):
        t0 = y / denom
        for x in range(size):
            px[x, y] = lerp(C1, C2, (x + y) / denom)
    return img


def gradient_rect(w, h):
    img = Image.new("RGB", (w, h))
    px = img.load()
    denom = (w - 1) + (h - 1)
    for y in range(h):
        for x in range(w):
            px[x, y] = lerp(C1, C2, (x + y) / denom)
    return img


def draw_full(supersample):
    size = 1024 * supersample
    bg = gradient(size)
    bg = bg.convert("RGBA")

    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    d.rounded_rectangle(
        (312, 300, 712, 724), radius=48 * supersample, fill=WHITE + (234,)
    )
    d.rounded_rectangle(
        (372, 372, 652, 416), radius=22 * supersample, fill=C1 + (255,)
    )
    d.rounded_rectangle(
        (372, 452, 652, 496), radius=22 * supersample, fill=C2 + (255,)
    )
    d.rounded_rectangle(
        (372, 532, 572, 576), radius=22 * supersample, fill=C1 + (255,)
    )

    icon = Image.alpha_composite(bg, overlay)
    if supersample > 1:
        icon = icon.resize((1024, 1024), Image.Resampling.LANCZOS)
    return icon


def draw_foreground(supersample):
    size = 1024 * supersample
    fg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(fg)
    d.rounded_rectangle(
        (312 * supersample, 300 * supersample, 712 * supersample, 724 * supersample),
        radius=48 * supersample, fill=WHITE + (234,)
    )
    d.rounded_rectangle(
        (372 * supersample, 372 * supersample, 652 * supersample, 416 * supersample),
        radius=22 * supersample, fill=C1 + (255,)
    )
    d.rounded_rectangle(
        (372 * supersample, 452 * supersample, 652 * supersample, 496 * supersample),
        radius=22 * supersample, fill=C2 + (255,)
    )
    d.rounded_rectangle(
        (372 * supersample, 532 * supersample, 572 * supersample, 576 * supersample),
        radius=22 * supersample, fill=C1 + (255,)
    )
    if supersample > 1:
        fg = fg.resize((1024, 1024), Image.Resampling.LANCZOS)
    return fg


def feature_graphic(supersample):
    w, h = 1024 * supersample, 500 * supersample
    bg = gradient_rect(w, h).convert("RGBA")
    d = ImageDraw.Draw(bg)

    icon = draw_full(supersample).resize(
        (320 * supersample, 320 * supersample), Image.Resampling.LANCZOS
    )
    bg.paste(icon, (w - 320 * supersample - 100 * supersample, (h - 320 * supersample) // 2))

    font_main = None
    font_sub = None
    for fp, size in [
        (r"C:\Windows\Fonts\msyhbd.ttc", 120 * supersample),
        (r"C:\Windows\Fonts\seguisb.ttf", 120 * supersample),
        (r"C:\Windows\Fonts\arialbd.ttf", 120 * supersample),
    ]:
        try:
            font_main = ImageFont.truetype(fp, size)
            break
        except OSError:
            continue
    for fp, size in [
        (r"C:\Windows\Fonts\msyh.ttc", 40 * supersample),
        (r"C:\Windows\Fonts\segoeui.ttf", 40 * supersample),
        (r"C:\Windows\Fonts\arial.ttf", 40 * supersample),
    ]:
        try:
            font_sub = ImageFont.truetype(fp, size)
            break
        except OSError:
            continue
    if font_main is None:
        font_main = ImageFont.load_default()
    if font_sub is None:
        font_sub = font_main

    d.text((100 * supersample, 140 * supersample), "freepdf", font=font_main, fill=WHITE)
    d.text((104 * supersample, 330 * supersample), "纯本地 PDF 阅读器", font=font_sub, fill=WHITE)

    if supersample > 1:
        bg = bg.resize((1024, 500), Image.Resampling.LANCZOS)
    return bg


def opaque(img, name, alpha_ok=True):
    img_rgba = img.convert("RGBA")
    w, h = img_rgba.size
    pts = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1),
           (w // 2, h // 2), (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]
    px = img_rgba.load()
    bad = [p for p in pts if px[p][3] != 255]
    if bad:
        raise SystemExit(f"FAIL {name}: transparent pixels at {bad}")
    print(f"OK   {name}: {w}x{h} fully opaque")


def main():
    icon = draw_full(SS)
    fg = draw_foreground(SS)
    bg = gradient(1024)
    fg_feature = feature_graphic(SS)

    icon_rgb = icon.convert("RGB")
    fg_rgb = fg.convert("RGB")

    icon_rgb.resize((512, 512), Image.Resampling.LANCZOS).save(f"{OUT_DIR}\\app_icon_512.png")
    icon_rgb.resize((216, 216), Image.Resampling.LANCZOS).save(f"{OUT_DIR}\\app_icon_216.png")
    icon.save(f"{OUT_DIR}\\startIcon.png")
    bg.save(f"{OUT_DIR}\\icon_background.png")
    fg.save(f"{OUT_DIR}\\icon_foreground.png")
    fg_feature.convert("RGB").save(f"{OUT_DIR}\\feature_graphic.png")

    for name, img in [
        ("app_icon_512.png", Image.open(f"{OUT_DIR}\\app_icon_512.png")),
        ("app_icon_216.png", Image.open(f"{OUT_DIR}\\app_icon_216.png")),
        ("startIcon.png", icon),
        ("icon_background.png", Image.open(f"{OUT_DIR}\\icon_background.png")),
        ("icon_foreground.png", Image.open(f"{OUT_DIR}\\icon_foreground.png")),
        ("feature_graphic.png", Image.open(f"{OUT_DIR}\\feature_graphic.png")),
    ]:
        if name == "icon_foreground.png":
            img_rgba = img.convert("RGBA")
            w, h = img_rgba.size
            px = img_rgba.load()
            corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
            if any(px[p][3] != 0 for p in corners):
                raise SystemExit(f"FAIL {name}: corners not transparent")
            if px[(w // 2, h // 2)][3] == 0:
                raise SystemExit(f"FAIL {name}: center is empty")
            print(f"OK   {name}: {w}x{h} transparent corners + opaque content")
            continue
        if img.mode != "RGBA":
            print(f"OK   {name}: {img.size} mode={img.mode} (no alpha channel)")
            continue
        opaque(img, name)


if __name__ == "__main__":
    main()
