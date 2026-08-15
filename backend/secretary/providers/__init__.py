"""
اختيار المزوّد.

المزوّد بيتحدّد من SEKERTER_PROVIDER في .env، والتبديل بينهم مايتطلّبش أي
تغيير في الكود — الفكرة إنك تجرّب الاتنين على كلامك الحقيقي وتقارن.
"""

from __future__ import annotations

from django.conf import settings

from .base import (
    AssistantTurn,
    ModelReply,
    Provider,
    ProviderError,
    ToolCall,
    ToolResult,
    ToolResultsTurn,
    ToolSpec,
    Turn,
    UserTurn,
)

__all__ = [
    "AssistantTurn",
    "ModelReply",
    "Provider",
    "ProviderError",
    "ToolCall",
    "ToolResult",
    "ToolResultsTurn",
    "ToolSpec",
    "Turn",
    "UserTurn",
    "get_provider",
]


def get_provider() -> Provider:
    name = settings.SEKERTER_PROVIDER

    if name == "claude":
        from .claude import build

        return build()

    if name == "deepseek":
        from .deepseek import build

        return build()

    raise ProviderError(
        f"مزوّد غير معروف: {name!r}. المتاح: claude أو deepseek."
    )
