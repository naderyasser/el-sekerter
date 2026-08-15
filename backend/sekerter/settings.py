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

ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "").strip()
SEKERTER_EFFORT = os.environ.get("SEKERTER_EFFORT", "low").strip() or "low"
