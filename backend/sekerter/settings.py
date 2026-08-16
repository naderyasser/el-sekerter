"""
إعدادات سيرفر السكرتير الخاص.

السيرفر ده مالوش قاعدة بيانات عن قصد: المواعيد كلها متخزّنة على الموبايل،
والسيرفر دوره الوحيد إنه يفهم كلام صاحب العمل ويرجّع أوامر. يعني لو السيرفر
وقع، التذكيرات المجدولة على الجهاز تفضل شغالة زي ما هي.
"""

import os
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent

load_dotenv(BASE_DIR / ".env")


def _require(name: str) -> str:
    """يقرا متغيّر لازم يكون موجود، ويقع بصوت عالي بدل ما يشتغل ناقص."""
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(
            f"المتغيّر {name} مش متظبّط. انسخ backend/.env.example باسم "
            f"backend/.env واملاه."
        )
    return value


DEBUG = os.environ.get("DJANGO_DEBUG", "0") == "1"

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "").strip()
if not SECRET_KEY:
    if DEBUG:
        SECRET_KEY = "insecure-dev-key-do-not-use-in-production"
    else:
        raise RuntimeError("DJANGO_SECRET_KEY لازم يتظبّط لما DJANGO_DEBUG=0")

ALLOWED_HOSTS = [
    h.strip()
    for h in os.environ.get("DJANGO_ALLOWED_HOSTS", "127.0.0.1,localhost").split(",")
    if h.strip()
]

INSTALLED_APPS = [
    "corsheaders",
    "rest_framework",
    "secretary",
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.common.CommonMiddleware",
]

ROOT_URLCONF = "sekerter.urls"
WSGI_APPLICATION = "sekerter.wsgi.application"

# مفيش قاعدة بيانات — البيانات كلها على الموبايل.
DATABASES = {}

TEMPLATES = []

LANGUAGE_CODE = "ar"
TIME_ZONE = "UTC"
USE_I18N = False
USE_TZ = True

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# التطبيق موبايل، فمفيش أوريجن ويب يتحط في اللستة. الحماية من التوكن مش من CORS.
CORS_ALLOW_ALL_ORIGINS = True

REST_FRAMEWORK = {
    # التوثيق بتوكن ثابت واحد (مستخدم واحد، جهاز واحد) — شوف secretary/auth.py
    "DEFAULT_AUTHENTICATION_CLASSES": [],
    "DEFAULT_PERMISSION_CLASSES": ["secretary.auth.HasSekerterToken"],
    "UNAUTHENTICATED_USER": None,
}

# ── إعدادات السكرتير ───────────────────────────────────────────────────────
SEKERTER_API_TOKEN = os.environ.get("SEKERTER_API_TOKEN", "").strip()
if not SEKERTER_API_TOKEN and not DEBUG:
    raise RuntimeError("SEKERTER_API_TOKEN لازم يتظبّط لما DJANGO_DEBUG=0")

# ── السيرفر اللي بيفهم الكلام ─────────────────────────────────────────────
#
# عنوان السيرفر ومفتاحه، من غير أي أسماء شركات. حط العنوان وخلاص.
SEKERTER_BASE_URL = os.environ.get("SEKERTER_BASE_URL", "").strip()
SEKERTER_API_KEY = os.environ.get("SEKERTER_API_KEY", "").strip()

# صيغة السيرفر — الحاجة الوحيدة اللي لازم تعرفها عنه:
#   messages → POST /v1/messages          (المفتاح في هيدر x-api-key)
#   chat     → POST /v1/chat/completions  (المفتاح في هيدر Authorization)
# لو مو متأكد، جرّب messages وشوف. try_model يقول لك على طول.
SEKERTER_FORMAT = (
    os.environ.get("SEKERTER_FORMAT", "messages").strip().lower() or "messages"
)

# اسم الموديل زي ما سيرفرك يعرفه. فاضي = افتراضي الصيغة.
SEKERTER_MODEL = os.environ.get("SEKERTER_MODEL", "").strip()

# إزاي الموديل يطلّع الأوامر:
#   native → استدعاء أدوات حقيقي. أدق، ويحتاج سيرفر يدعمه.
#   text   → الأوامر كـJSON جوّه نص الرد. يشتغل على أي سيرفر.
# بعض السيرفرات تستقبل tools وترميها في صمت — وساعتها الموديل يقول «أبشر»
# وما يتسجّل ولا موعد. try_model يكشف الحالة دي؛ لو كشفها حط text.
SEKERTER_TOOLS = (
    os.environ.get("SEKERTER_TOOLS", "native").strip().lower() or "native"
)

# مستوى تفكير الموديل — يشتغل مع أنثروبيك المباشرة بس، والبوابات تتجاهله.
SEKERTER_EFFORT = os.environ.get("SEKERTER_EFFORT", "low").strip() or "low"

# ── الاتصال المباشر بالسحابة (اختياري) ────────────────────────────────────
# لو ما حطيتش SEKERTER_BASE_URL، بنرجع للاتصال المباشر بمزوّد سحابي،
# والاختيار بينهم من هنا.
SEKERTER_PROVIDER = (
    os.environ.get("SEKERTER_PROVIDER", "claude").strip().lower() or "claude"
)

ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "").strip()
ANTHROPIC_BASE_URL = os.environ.get("ANTHROPIC_BASE_URL", "").strip()

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY", "").strip()
DEEPSEEK_BASE_URL = os.environ.get("DEEPSEEK_BASE_URL", "").strip()
