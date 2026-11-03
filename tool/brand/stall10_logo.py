"""Draws the Stall 10 logo -- a bold "1" beside a flying disc that forms the
"0", with a motion trail, on the app's deep green -- and writes every app
icon from it.

Run from the repo root (needs Pillow: `pip install pillow`):

    python tool/brand/stall10_logo.py

It overwrites assets/brand/stall10_logo.png and the Android, iOS, macOS and
Windows launcher icons.
"""
import json
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

GREEN_TOP = (38, 76, 54)
GREEN_BOTTOM = (18, 36, 26)
LIME = (215, 240, 106)
LIME_SHADE = (178, 204, 70)
LIME_EDGE = (120, 146, 40)
LIME_RIM = (242, 252, 190)
WHITE = (246, 248, 242)

S = 4  # supersampling


def gradient(size, top, bottom):
    a = Image.new('RGB', (size, size), top)
    b = Image.new('RGB', (size, size), bottom)
    mask = Image.linear_gradient('L').resize((size, size))
    return Image.composite(b, a, mask)


def ellipse(cx, cy, rx, ry, angle_deg, n=720):
    a = math.radians(angle_deg)
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x, y = rx * math.cos(t), ry * math.sin(t)
        pts.append((cx + x * math.cos(a) - y * math.sin(a),
                    cy + x * math.sin(a) + y * math.cos(a)))
    return pts


def mask_of(W, pts):
    m = Image.new('L', (W, W), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m


def soft_shadow(img, pts_or_mask, W, dx, dy, blur, alpha):
    m = pts_or_mask if isinstance(pts_or_mask, Image.Image) else mask_of(
        W, pts_or_mask)
    m = ImageChops.offset(m, int(dx), int(dy)).filter(
        ImageFilter.GaussianBlur(blur))
    shade = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    shade.putalpha(m.point(lambda v: v * alpha // 255))
    return Image.alpha_composite(img, shade)


def draw(font_path, size=1024):
    W = size * S
    img = gradient(W, GREEN_TOP, GREEN_BOTTOM).convert('RGBA')

    cx, cy = W * 0.615, W * 0.47
    rx, ry = W * 0.225, W * 0.295
    tilt = -18

    # Soft lime glow behind the disc.
    glow = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(glow).polygon(ellipse(cx, cy, rx * 1.15, ry * 1.1, tilt),
                                 fill=LIME + (55,))
    img = Image.alpha_composite(
        img, glow.filter(ImageFilter.GaussianBlur(W * 0.08)))

    # Motion trail: three tapered swooshes arcing in under the "1".
    trail = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    td = ImageDraw.Draw(trail)
    for off, width, color in [(-0.075, 0.034, LIME_SHADE),
                              (0.0, 0.050, LIME),
                              (0.075, 0.034, LIME_SHADE)]:
        top, bot = [], []
        steps = 80
        for k in range(steps + 1):
            t = k / steps
            x = W * (0.10 + 0.44 * t)
            y = W * (0.86 - 0.20 * t) + W * off * (1 - 0.55 * t)
            y -= W * 0.07 * math.sin(math.pi * t)
            half = W * width * (t ** 1.6) * 0.5
            top.append((x, y - half))
            bot.append((x, y + half))
        td.polygon(top + bot[::-1], fill=color + (255,))
    img = Image.alpha_composite(img, trail)

    # The "1".
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(font_path, int(W * 0.64))
    text = '1'
    bbox = d.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = W * 0.265 - tw / 2 - bbox[0]
    ty = W * 0.47 - th / 2 - bbox[1]
    one = Image.new('L', (W, W), 0)
    ImageDraw.Draw(one).text((tx, ty), text, font=font, fill=255)
    img = soft_shadow(img, one, W, W * 0.012, W * 0.022, W * 0.014, 120)
    white = Image.new('RGBA', (W, W), WHITE + (255,))
    img.paste(white, (0, 0), one)

    # The disc, the "0": tilted mid-flight, with visible rim thickness.
    outer = ellipse(cx, cy, rx, ry, tilt)
    img = soft_shadow(img, outer, W, W * 0.03, W * 0.04, W * 0.025, 130)
    d = ImageDraw.Draw(img)
    # the rim's underside, peeking out below/right
    d.polygon(ellipse(cx + W * 0.018, cy + W * 0.026, rx, ry, tilt),
              fill=LIME_EDGE)
    # top surface, shaded from a light upper-left
    top_mask = mask_of(W, outer)
    shade = gradient(W, LIME, LIME_SHADE).convert('RGBA')
    img.paste(shade, (0, 0), top_mask)
    d = ImageDraw.Draw(img)

    def ring(k_out, k_in):
        return ImageChops.subtract(
            mask_of(W, ellipse(cx, cy, rx * k_out, ry * k_out, tilt)),
            mask_of(W, ellipse(cx, cy, rx * k_in, ry * k_in, tilt)))

    # flight ring groove, then the hole that makes it a "0"
    img.paste(Image.new('RGBA', (W, W), LIME_EDGE + (255,)), (0, 0),
              ring(0.825, 0.80))
    hole = ellipse(cx, cy, rx * 0.52, ry * 0.60, tilt)
    # the hole shows the rim's inner wall at the top-left
    d.polygon(hole, fill=LIME_EDGE)
    d.polygon(ellipse(cx + W * 0.012, cy + W * 0.018, rx * 0.52, ry * 0.60,
                      tilt), fill=GREEN_BOTTOM)
    # re-clip the inner wall to the hole
    hole_mask = mask_of(W, hole)
    inner = img.copy()
    img = Image.alpha_composite(
        img, Image.new('RGBA', (W, W), (0, 0, 0, 0)))
    img.paste(inner, (0, 0), hole_mask)
    # highlight along the upper-left of the rim: a band of the rim, cut to
    # a wedge pointing at the light, softened
    wedge = Image.new('L', (W, W), 0)
    a0, a1 = math.radians(-165), math.radians(-95)
    reach = W
    ImageDraw.Draw(wedge).polygon(
        [(cx, cy)] + [(cx + reach * math.cos(a0 + (a1 - a0) * i / 20),
                       cy + reach * math.sin(a0 + (a1 - a0) * i / 20))
                      for i in range(21)], fill=255)
    wedge = wedge.filter(ImageFilter.GaussianBlur(W * 0.03))
    band = ImageChops.multiply(ring(0.955, 0.895), wedge)
    img.paste(Image.new('RGBA', (W, W), LIME_RIM + (255,)), (0, 0), band)

    return img.resize((size, size), Image.LANCZOS)


def rounded(img, radius_frac=0.2237):
    """Transparent corners, like a desktop app icon."""
    size = img.size[0]
    m = Image.new('L', (size * S, size * S), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [0, 0, size * S - 1, size * S - 1], radius=size * S * radius_frac,
        fill=255)
    m = m.resize((size, size), Image.LANCZOS)
    out = img.convert('RGBA')
    out.putalpha(m)
    return out


def mac_icon(img):
    """macOS style: a rounded square inset on a transparent 1024 canvas."""
    inner = rounded(img.resize((824, 824), Image.LANCZOS), 0.2237)
    canvas = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
    shadow = Image.new('L', (1024, 1024), 0)
    ImageDraw.Draw(shadow).rounded_rectangle(
        [100, 112, 924, 936], radius=184, fill=90)
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    canvas.paste((0, 0, 0, 255), (0, 0), shadow)
    canvas.alpha_composite(inner, (100, 100))
    return canvas


def main():
    master = draw('assets/fonts/Inter-ExtraBold.ttf', 1024)
    square = master.convert('RGB')
    corners = rounded(master, 0.18)

    # In-app logo (the app rounds its corners itself).
    square.save('assets/brand/stall10_logo.png')

    # iOS: full-bleed squares, no transparency; iOS rounds them.
    ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    with open(os.path.join(ios, 'Contents.json'), encoding='utf-8') as f:
        images = json.load(f)['images']
    for i in images:
        points = float(i['size'].split('x')[0])
        px = round(points * int(i['scale'].rstrip('x')))
        square.resize((px, px), Image.LANCZOS).save(
            os.path.join(ios, i['filename']))

    # macOS.
    mac = mac_icon(master)
    for px in (16, 32, 64, 128, 256, 512, 1024):
        mac.resize((px, px), Image.LANCZOS).save(
            f'macos/Runner/Assets.xcassets/AppIcon.appiconset/'
            f'app_icon_{px}.png')

    # Android launcher icons.
    for folder, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                       ('xxhdpi', 144), ('xxxhdpi', 192)]:
        corners.resize((px, px), Image.LANCZOS).save(
            f'android/app/src/main/res/mipmap-{folder}/ic_launcher.png')

    # Windows.
    corners.save('windows/runner/resources/app_icon.ico',
                 sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
    print('Wrote the logo and every app icon.')


if __name__ == '__main__':
    main()
