"""Draws the Stall 10 logo -- a bold "1" beside a flying disc that forms the
"0", with a motion trail -- and writes every app icon from it.

The logo is an indigo disc and an ink "1" on white: the website's palette,
so the icon matches what users see in the app and on the site.

Run from apps/mobile (needs Pillow: `pip install pillow`):

    python tool/brand/stall10_logo.py

It overwrites assets/brand/stall10_logo.png, the Android and iOS launcher
icons, and the website's logo and favicon (apps/web/public and
firebase/hosting).
"""
import json
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

# White with an indigo disc: the website's accent (#5348B2 family), so the
# icon promises the colours users find inside.
BG_TOP = (255, 255, 255)       # background, top
BG_BOTTOM = (242, 243, 247)    # background, bottom (and the disc's hole)
DISC = (99, 86, 204)           # disc top surface, trail
DISC_SHADE = (84, 73, 173)     # disc shading, outer trails
DISC_EDGE = (54, 47, 112)      # disc rim underside and flight ring
DISC_RIM = (193, 188, 235)     # rim highlight
WHITE = (23, 26, 46)           # the "1" (site ink #171A2E)

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
    img = gradient(W, BG_TOP, BG_BOTTOM).convert('RGBA')

    cx, cy = W * 0.615, W * 0.47
    rx, ry = W * 0.225, W * 0.295
    tilt = -18

    # Soft glow behind the disc.
    glow = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(glow).polygon(ellipse(cx, cy, rx * 1.15, ry * 1.1, tilt),
                                 fill=DISC + (28,))
    img = Image.alpha_composite(
        img, glow.filter(ImageFilter.GaussianBlur(W * 0.08)))

    # Motion trail: three tapered swooshes arcing in under the "1".
    trail = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    td = ImageDraw.Draw(trail)
    for off, width, color in [(-0.075, 0.034, DISC_SHADE),
                              (0.0, 0.050, DISC),
                              (0.075, 0.034, DISC_SHADE)]:
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
              fill=DISC_EDGE)
    # top surface, shaded from a light upper-left
    top_mask = mask_of(W, outer)
    shade = gradient(W, DISC, DISC_SHADE).convert('RGBA')
    img.paste(shade, (0, 0), top_mask)
    d = ImageDraw.Draw(img)

    def ring(k_out, k_in):
        return ImageChops.subtract(
            mask_of(W, ellipse(cx, cy, rx * k_out, ry * k_out, tilt)),
            mask_of(W, ellipse(cx, cy, rx * k_in, ry * k_in, tilt)))

    # flight ring groove, then the hole that makes it a "0"
    img.paste(Image.new('RGBA', (W, W), DISC_EDGE + (255,)), (0, 0),
              ring(0.825, 0.80))
    hole = ellipse(cx, cy, rx * 0.52, ry * 0.60, tilt)
    # the hole shows the rim's inner wall at the top-left
    d.polygon(hole, fill=DISC_EDGE)
    d.polygon(ellipse(cx + W * 0.012, cy + W * 0.018, rx * 0.52, ry * 0.60,
                      tilt), fill=BG_BOTTOM)
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
    img.paste(Image.new('RGBA', (W, W), DISC_RIM + (255,)), (0, 0), band)

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

    # Android launcher icons.
    for folder, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                       ('xxhdpi', 144), ('xxxhdpi', 192)]:
        corners.resize((px, px), Image.LANCZOS).save(
            f'android/app/src/main/res/mipmap-{folder}/ic_launcher.png')

    # Website: logo (pages round its corners) and favicon.
    for site in ('../web/public', '../../firebase/hosting'):
        square.resize((256, 256), Image.LANCZOS).save(f'{site}/logo.png')
        corners.resize((64, 64), Image.LANCZOS).save(f'{site}/favicon.png')
    print('Wrote the logo, every app icon and the website icons.')


if __name__ == '__main__':
    main()
