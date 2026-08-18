"""توليد لوجو التطبيق وكل الأصول المشتقة منه.

شغّله من مجلد app/ بعد أي تعديل في التصميم:
    python3 tool/make_logo.py
    dart run flutter_launcher_icons

بيولّد:
  assets/logo/icon.png             الأيقونة الكاملة (مصدر المولّد)
  assets/logo/icon_foreground.png  طبقة الشكل التكيفي (أندرويد ٨+)
  assets/logo/icon_background.png  خلفية الشكل التكيفي
  assets/logo/logo.png             اللوجو المستخدم جوه التطبيق
  res/drawable-*/ic_stat_sekerter  أيقونة شريط الحالة (قناع أبيض)
"""
from PIL import Image, ImageDraw, ImageFont
import os

FONT = 'assets/fonts/Almarai-ExtraBold.ttf'
OUT = 'assets/logo'
RES = 'android/app/src/main/res'
S = 1024

TOP = (27, 138, 104)      # حوالين لون الثيم 0xFF166D53
BOTTOM = (10, 77, 58)
AMBER = (244, 182, 63)


def gradient(size, top, bottom):
    img = Image.new('RGB', (size, size))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        for x in range(size):
            px[x, y] = tuple(
                round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)
            )
    return img


def rounded_mask(size, radius):
    m = Image.new('L', (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=radius, fill=255
    )
    return m


def glyph_layer(size, glyph_ratio=0.62, dot=True):
    """حرف «س» أبيض + نقطة تنبيه، على شفاف. دقة مضاعفة وتنزيل للتنعيم."""
    big = size * 2
    layer = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    font = ImageFont.truetype(FONT, int(big * glyph_ratio))
    bbox = d.textbbox((0, 0), 'س', font=font)
    x = (big - (bbox[2] - bbox[0])) // 2 - bbox[0]
    y = (big - (bbox[3] - bbox[1])) // 2 - bbox[1] - int(big * 0.02)
    d.text((x, y), 'س', font=font, fill=(255, 255, 255, 255))
    if dot:
        r = int(big * 0.075)
        cx, cy = int(big * 0.735), int(big * 0.30)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=AMBER + (255,))
    return layer.resize((size, size), Image.LANCZOS)


os.makedirs(OUT, exist_ok=True)

base = gradient(S, TOP, BOTTOM).convert('RGBA')
icon = Image.new('RGBA', (S, S), (0, 0, 0, 0))
icon.paste(base, (0, 0), rounded_mask(S, int(S * 0.22)))
icon.alpha_composite(glyph_layer(S))
icon.save(f'{OUT}/icon.png')

fg = Image.new('RGBA', (S, S), (0, 0, 0, 0))
small = glyph_layer(int(S * 0.60))
off = (S - small.width) // 2
fg.alpha_composite(small, (off, off))
fg.save(f'{OUT}/icon_foreground.png')

gradient(S, TOP, BOTTOM).save(f'{OUT}/icon_background.png')
icon.resize((512, 512), Image.LANCZOS).save(f'{OUT}/logo.png')

for dpi, px in [('mdpi', 24), ('hdpi', 36), ('xhdpi', 48),
                ('xxhdpi', 72), ('xxxhdpi', 96)]:
    dd = f'{RES}/drawable-{dpi}'
    os.makedirs(dd, exist_ok=True)
    glyph_layer(px, glyph_ratio=0.85, dot=False).save(
        f'{dd}/ic_stat_sekerter.png'
    )

# لوجو شاشة الفتح بدقة واحدة
os.makedirs(f'{RES}/drawable-nodpi', exist_ok=True)
icon.resize((512, 512), Image.LANCZOS).save(
    f'{RES}/drawable-nodpi/splash_logo.png'
)

print('تمام — اتولدوا كلهم')
