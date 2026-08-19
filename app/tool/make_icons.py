"""يولّد كل أصول هوية التطبيق من رسمة واحدة: ساعة على شكل فقاعة كلام —
«سكرتير بيتكلم وبيمسك المواعيد».

    python3 tool/make_icons.py

بيكتب:
- assets/logo/{icon,icon_background,icon_foreground,logo}.png — أصول
  flutter_launcher_icons (dart run flutter_launcher_icons بيطلّع نفس الناتج)
- android res: أيقونات المشغّل القديمة والتكيفية + ic_stat_sekerter
  (أيقونة الإشعار — أبيض على شفاف) + splash_logo لشاشة الفتح
- iOS: كل مقاسات AppIcon

العقارب والعلامات مقطوعة من الجسم الأبيض (شفافة) عشان نفس الرسمة تشتغل
foreground و monochrome في الأيقونة التكيفية، وأيقونة إشعار سليمة
(أندرويد بياخد قناة الشفافية بس).

مش محتاج غير Pillow: pip install pillow
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw

APP = Path(__file__).resolve().parents[1]
RES = APP / "android/app/src/main/res"
IOS = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
LOGO = APP / "assets/logo"

TOP = (31, 138, 104)     # 0x1F8A68 — أفتح من الـ seed شوية
BOTTOM = (13, 70, 53)    # 0x0D4635 — أغمق منه

MASK = 2048  # دقة رسم العلامة قبل التصغير


def mark_mask() -> Image.Image:
    """فقاعة-ساعة بيضا (قناة L): 255 = أبيض، 0 = مقطوع/شفاف."""
    s = MASK
    m = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(m)

    cx, cy, r = 0.5 * s, 0.485 * s, 0.30 * s

    # جسم الفقاعة: دايرة + ذيل لتحت-يمين (اتجاه المتكلم في RTL)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    a1, a2 = math.radians(30), math.radians(80)
    apex = math.radians(55)
    d.polygon(
        [
            (cx + r * math.cos(a1), cy + r * math.sin(a1)),
            (cx + 1.48 * r * math.cos(apex), cy + 1.48 * r * math.sin(apex)),
            (cx + r * math.cos(a2), cy + r * math.sin(a2)),
        ],
        fill=255,
    )

    def dot(x, y, rad, val):
        d.ellipse([x - rad, y - rad, x + rad, y + rad], fill=val)

    # علامات 12 و3 و6 و9 — مقطوعة
    tick_r, tick_d = 0.235 * s, 0.030 * s
    for ang in (270, 0, 90, 180):
        t = math.radians(ang)
        dot(cx + tick_r * math.cos(t), cy + tick_r * math.sin(t), tick_d, 0)

    # عقارب على 10:10 — مقطوعة، بأطراف مدوّرة
    def hand(clock_deg, length, width):
        t = math.radians(clock_deg - 90)
        x2, y2 = cx + length * math.cos(t), cy + length * math.sin(t)
        d.line([cx, cy, x2, y2], fill=0, width=int(width))
        dot(x2, y2, width / 2, 0)

    hand(300, 0.150 * s, 0.052 * s)  # عقرب الساعات → 10
    hand(60, 0.205 * s, 0.046 * s)   # عقرب الدقايق → 2
    dot(cx, cy, 0.045 * s, 0)        # مركز مقطوع
    dot(cx, cy, 0.018 * s, 255)      # نقطة بيضا صغيرة في قلب المركز

    return m


def gradient(size: int) -> Image.Image:
    g = Image.linear_gradient("L").resize((size, size))
    top = Image.new("RGB", (size, size), TOP)
    bottom = Image.new("RGB", (size, size), BOTTOM)
    return Image.composite(bottom, top, g)


def white_mark(size: int, mark: Image.Image, scale: float) -> Image.Image:
    """العلامة البيضا لوحدها على شفاف، بحجم نسبي من الكانفس."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ms = int(size * scale)
    mm = mark.resize((ms, ms), Image.LANCZOS)
    white = Image.new("RGBA", (ms, ms), (255, 255, 255, 255))
    img.paste(white, ((size - ms) // 2, (size - ms) // 2), mm)
    return img


def compose_icon(size: int, mark: Image.Image, *, corner: float, mark_scale: float) -> Image.Image:
    """خلفية متدرجة + العلامة البيضا، بزوايا مدوّرة اختياريًا (corner كنسبة)."""
    big = max(size * 4, 512)  # نرسم أكبر وننزّل عشان النعومة
    icon = gradient(big).convert("RGBA")

    ms = int(big * mark_scale)
    mm = mark.resize((ms, ms), Image.LANCZOS)
    white = Image.new("RGBA", (ms, ms), (255, 255, 255, 255))
    icon.paste(white, ((big - ms) // 2, (big - ms) // 2), mm)

    if corner > 0:
        shape = Image.new("L", (big, big), 0)
        ImageDraw.Draw(shape).rounded_rectangle(
            [0, 0, big - 1, big - 1], radius=int(big * corner), fill=255
        )
        icon.putalpha(shape)

    return icon.resize((size, size), Image.LANCZOS)


def main() -> None:
    mark = mark_mask()

    # أصول flutter_launcher_icons — نفس اللي بيتولد منها كل حاجة تانية
    LOGO.mkdir(parents=True, exist_ok=True)
    compose_icon(1024, mark, corner=0.20, mark_scale=0.74).save(LOGO / "icon.png")
    gradient(1024).save(LOGO / "icon_background.png")
    white_mark(1024, mark, 0.56).save(LOGO / "icon_foreground.png")
    # اللوجو اللي بيتعرض جوّه التطبيق (الإعدادات وغيرها)
    compose_icon(512, mark, corner=0.20, mark_scale=0.74).save(LOGO / "logo.png")

    dpis = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for dpi, k in dpis.items():
        # الأيقونة القديمة (قبل أندرويد 8): مربع بزوايا مدوّرة — 48dp
        compose_icon(int(48 * k), mark, corner=0.20, mark_scale=0.74).save(
            RES / f"mipmap-{dpi}" / "ic_launcher.png"
        )
        # طبقات الأيقونة التكيفية (8.0+) — 108dp، والعلامة جوّه المنطقة
        # الآمنة (66dp) عشان أي قناع دايرة/مربع ما يقصّهاش
        px = int(108 * k)
        gradient(px).save(RES / f"drawable-{dpi}" / "ic_launcher_background.png")
        white_mark(px, mark, 0.56).save(RES / f"drawable-{dpi}" / "ic_launcher_foreground.png")
        # أيقونة شريط الإشعارات — 24dp، أندرويد بيستخدم الشفافية بس
        white_mark(int(24 * k), mark, 0.94).save(RES / f"drawable-{dpi}" / "ic_stat_sekerter.png")

    # لوجو شاشة الفتح: العلامة البيضا على خلفية splash_background الخضرا
    white_mark(512, mark, 0.80).save(RES / "drawable-nodpi" / "splash_logo.png")

    # iOS — مربع كامل من غير تدوير ولا شفافية (النظام بيدوّر بنفسه)
    ios_sizes = {
        "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40, "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29, "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80, "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120, "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76, "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167, "Icon-App-1024x1024@1x.png": 1024,
    }
    for name, px in ios_sizes.items():
        compose_icon(px, mark, corner=0.0, mark_scale=0.74).convert("RGB").save(IOS / name)

    print("done")


if __name__ == "__main__":
    main()
