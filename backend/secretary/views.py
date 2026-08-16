"""نقاط النهاية."""

import logging

from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from .brain import BrainUnavailable, chat  # noqa: F401
from .serializers import ChatRequestSerializer

logger = logging.getLogger(__name__)


@api_view(["GET"])
@permission_classes([AllowAny])
def root(request):
    """
    صفحة الجذر.

    مافيش واجهة ويب — السكرتير تطبيق موبايل والسيرفر بيرد على مسارين بس.
    من غير الصفحة دي، اللي يفتح الدومين في المتصفح يشوف 404 ويفتكر إن
    النشر باظ. حصل فعلًا.
    """
    return Response(
        {
            "service": "sekerter",
            "status": "ok",
            "note": "سيرفر السكرتير الخاص. مافيش واجهة ويب — استخدم التطبيق.",
            "endpoints": {
                "health": "/api/secretary/health",
                "chat": "POST /api/secretary/chat",
            },
        }
    )


@api_view(["GET"])
@permission_classes([AllowAny])
def health(request):
    """فحص إن السيرفر واقف. من غير توكن عشان يشتغل مع مراقبة خارجية."""
    return Response({"status": "ok"})


@api_view(["POST"])
def chat_view(request):
    """
    الرسالة الواحدة: التطبيق بيبعت كلام صاحب العمل + مواعيده الحالية،
    والرد بيرجع نص + أوامر ينفّذها التطبيق محليًا.
    """
    serializer = ChatRequestSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data

    try:
        result = chat(
            message=data["message"],
            now_iso=data["now"],
            timezone=data["timezone"],
            appointments=data["appointments"],
            history=data["history"],
        )
    except BrainUnavailable as exc:
        # الرسالة نفسها معمولة عشان تتعرض للمستخدم، مش تتبيعة داخلية.
        return Response(
            {"detail": str(exc)}, status=status.HTTP_503_SERVICE_UNAVAILABLE
        )
    except Exception:
        logger.exception("chat failed")
        return Response(
            {"detail": "صار خطأ غير متوقع."},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )

    return Response(result)
