"""
اختيار السيرفر اللي هيفهم الكلام.

الطريقة العادية: تحط SEKERTER_BASE_URL وSEKERTER_API_KEY وخلاص — من غير
أي اسم شركة. الحاجة الوحيدة الباقية هي صيغة السيرفر (SEKERTER_FORMAT)،
وهي حاجة تقنية بحتة مالهاش علاقة بمين عامله:

    messages → POST /v1/messages
    chat     → POST /v1/chat/completions

ولو ما حطيتش عنوان، بنرجع للاتصال المباشر بمزوّد سحابي حسب
SEKERTER_PROVIDER. ده مسار قديم متسايب عشان اللي يبي يقارن.
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
    # عنوان متحطّط = سيرفرك، والصيغة هي اللي تحدّد شكل الطلب.
    if settings.SEKERTER_BASE_URL:
        return _by_format(
            settings.SEKERTER_FORMAT,
            base_url=settings.SEKERTER_BASE_URL,
            api_key=settings.SEKERTER_API_KEY,
        )

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


def _by_format(fmt: str, *, base_url: str, api_key: str) -> Provider:
    if not api_key:
        raise ProviderError("SEKERTER_API_KEY مو مضبوط على السيرفر.")

    if fmt == "messages":
        from .claude import ClaudeProvider

        return ClaudeProvider(
            api_key=api_key,
            model=settings.SEKERTER_MODEL,
            effort=settings.SEKERTER_EFFORT,
            base_url=base_url,
        )

    if fmt == "chat":
        from .deepseek import DeepSeekProvider

        return DeepSeekProvider(
            api_key=api_key,
            model=settings.SEKERTER_MODEL,
            base_url=base_url,
        )

    raise ProviderError(
        f"صيغة غير معروفة: {fmt!r}. المتاح: messages أو chat."
    )
