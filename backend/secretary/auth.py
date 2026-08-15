"""
توثيق بتوكن ثابت واحد.

المشروع لمستخدم واحد (صاحب العمل) على جهازه، فمفيش داعي لحسابات ولا JWT.
التطبيق بيبعت `Authorization: Bearer <SEKERTER_API_TOKEN>` في كل طلب.
لو المشروع اتوسّع لأكتر من مستخدم، الملف ده هو نقطة التغيير الوحيدة.
"""

import hmac

from django.conf import settings
from rest_framework.permissions import BasePermission


class HasSekerterToken(BasePermission):
    message = "توكن غير صالح."

    def has_permission(self, request, view) -> bool:
        expected = settings.SEKERTER_API_TOKEN
        if not expected:
            # مفيش توكن متظبّط: مسموح في التطوير المحلي بس، وممنوع تمامًا في
            # الإنتاج (settings.py بيقع من الأصل لو DEBUG=0 والتوكن فاضي).
            return bool(settings.DEBUG)

        header = request.META.get("HTTP_AUTHORIZATION", "")
        prefix = "Bearer "
        if not header.startswith(prefix):
            return False

        # مقارنة ثابتة الزمن حتى ما يتسربش طول التوكن الصح من زمن الرد.
        return hmac.compare_digest(header[len(prefix) :].strip(), expected)
