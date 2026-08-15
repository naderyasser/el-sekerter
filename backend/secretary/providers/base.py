"""
الشكل المحايد اللي حلقة الأدوات بتتكلم بيه، مستقل عن المزوّد.

`brain.py` بيشتغل بالأنواع اللي هنا بس؛ كل مزوّد بيترجم بينها وبين شكل الـAPI
بتاعه. كده منطق التحقق وحلقة الأدوات مكتوب مرة واحدة مهما كان المزوّد.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Protocol


class ProviderError(RuntimeError):
    """فشل نداء المزوّد. الرسالة معمولة عشان تتعرض للمستخدم."""


@dataclass(frozen=True)
class ToolCall:
    """استدعاء أداة واحد زي ما الموديل طلبه."""

    id: str
    name: str
    arguments: dict[str, Any]


@dataclass(frozen=True)
class ToolResult:
    call_id: str
    content: str
    is_error: bool = False


@dataclass(frozen=True)
class ModelReply:
    text: str = ""
    tool_calls: list[ToolCall] = field(default_factory=list)

    # مصنّفات الأمان رفضت الطلب. Claude بيبلّغ عنها صراحة؛ المزوّدين التانيين
    # بيرجّعوا رفض كنص عادي، فبتفضل False عندهم.
    refused: bool = False


# ── تمثيل المحادثة ─────────────────────────────────────────────────────────
# ثلاث أنواع أدوار بس: كلام المستخدم، رد الموديل (نص + استدعاءات)، ونتايج
# الأدوات. أي شكل تاني بيتبني منهم في المزوّد.


@dataclass(frozen=True)
class UserTurn:
    text: str


@dataclass(frozen=True)
class AssistantTurn:
    text: str
    tool_calls: list[ToolCall] = field(default_factory=list)


@dataclass(frozen=True)
class ToolResultsTurn:
    results: list[ToolResult]


Turn = UserTurn | AssistantTurn | ToolResultsTurn


@dataclass(frozen=True)
class ToolSpec:
    """تعريف أداة بشكل محايد. كل مزوّد بيحوّله لشكله."""

    name: str
    description: str
    parameters: dict[str, Any]


class Provider(Protocol):
    """اللي كل مزوّد لازم يوفّره."""

    name: str

    def complete(
        self,
        *,
        instructions: str,
        context: str,
        turns: list[Turn],
        tools: list[ToolSpec],
    ) -> ModelReply:
        """
        يبعت لفّة واحدة للموديل ويرجّع رده.

        [instructions] الجزء الثابت من البرومبت (اللي بيتكاش)، و[context] الجزء
        المتغيّر (الوقت الحالي والمواعيد). المزوّد اللي بيدعم التكاش بيفصلهم؛
        اللي مبيدعمش بيلزقهم.
        """
        ...
