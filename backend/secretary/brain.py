"""
حلقة الأدوات — محايدة تجاه المزوّد.

السيرفر ما بينفّذش الأدوات: بيسجّلها كأوامر ويرجّع للموديل «تمام» عشان يكمّل
كلامه، والتطبيق هو اللي ينفّذها فعليًا على قاعدة البيانات المحلية. عشان كده
الحلقة هنا مصطنعة بالكامل ومحدودة بعدد لفّات صغير.
"""

from __future__ import annotations

import datetime as dt
import logging
import zoneinfo
from typing import Any

from django.conf import settings

from . import text_protocol
from . import tools as tool_defs
from .prompt import INSTRUCTIONS, build_context
from .providers import (
    AssistantTurn,
    ProviderError,
    ToolResult,
    ToolResultsTurn,
    Turn,
    UserTurn,
    get_provider,
)

logger = logging.getLogger(__name__)

# حد أمان للحلقة. مزوّد بيبعت الأدوات واحدة واحدة (مش متوازية) بياكل لفّة
# لكل موعد + لفّة للرد النصي — الأربعة كانت بتقصقص «سجّل لي أربع مواعيد»
# عند التالت. تمنية بتغطي ست مواعيد متتالية مع لفّة تصحيح؛ اللي بيعدّيها
# غالبًا موديل بيلف حوالين نفسه، وأحسن نوقفه بدل ما نفضل ندفع.
MAX_TURNS = 8

# آخر كام رسالة من التاريخ بتتبعت. بيحدّ التكلفة ويخلّي السياق مركّز.
# لازم تساوي AppConfig.historyWindow في app/lib/core/config.dart.
MAX_HISTORY_MESSAGES = 20

BUSY_REPLY = "الخدمة مشغولة الحين، جرّب مرة ثانية بعد شوي."
REFUSAL_REPLY = "معليش، ما قدرت أتعامل مع هذا الطلب. ممكن تقوله بطريقة ثانية؟"


# استثناء المزوّد هو نفسه اللي الـview بيمسكه — اسم واحد بدل تحويل بينهم.
BrainUnavailable = ProviderError


def _normalise_at(payload: dict[str, Any], timezone: str) -> str | None:
    """
    يتأكد إن payload["at"] وقت ISO 8601 صالح، ويكمّل فرق التوقيت لو ناقص.

    الموديل كتير بيكتب «2026-08-17T17:00:00» من غير فرق توقيت. الرفض هنا
    كان أغلى غلطة في السيرفر: في الوضع النصّي مافيش لفّة تصحيح فالموعد
    بيتشال **في صمت** — الموديل يقول «أبشر سجّلتهم» والتالت مش موجود.
    وفي وضع الأدوات بيحرق لفّة تصحيح على حاجة إحنا عارفين إجابتها أصلًا:
    المنطقة الزمنية جاية مع الطلب نفسه، فنكمّلها بدالـه.
    """
    value = payload.get("at")
    if not isinstance(value, str):
        return "الوقت لازم يكون نص بصيغة ISO 8601."
    try:
        parsed = dt.datetime.fromisoformat(value)
    except ValueError:
        return (
            f"«{value}» مو صيغة ISO 8601 صالحة. "
            "المطلوب زي 2026-08-16T17:30:00+03:00."
        )
    if parsed.tzinfo is None:
        try:
            zone = zoneinfo.ZoneInfo(timezone)
        except (zoneinfo.ZoneInfoNotFoundError, ValueError, KeyError):
            return f"«{value}» ناقصها فرق التوقيت. زِد +03:00 مثلًا."
        payload["at"] = parsed.replace(tzinfo=zone).isoformat()
    return None


# الموديل بيكتب اسم القناة بالعربي أحيانًا، خصوصًا في الوضع النصّي حيث
# مافيش enum بيتفرض عليه. القيمة دي بيـswitch عليها التطبيق، فقيمة مش
# مفهومة معناها رسالة ما تنبعتش. الترجمة أرخص من ضياع الرسالة.
_CHANNELS = {
    "whatsapp": "whatsapp",
    "wa": "whatsapp",
    "واتساب": "whatsapp",
    "واتس": "whatsapp",
    "الواتس": "whatsapp",
    "واتس اب": "whatsapp",
    "sms": "sms",
    "رسالة": "sms",
    "رساله": "sms",
    "رسالة نصية": "sms",
    "نصية": "sms",
    "نصيه": "sms",
}


def _normalise_channel(payload: dict[str, Any]) -> str | None:
    """يوحّد اسم القناة في المكان. القيمة الفاضية = واتساب زي البرومبت."""
    raw = payload.get("channel")
    if raw is None or not str(raw).strip():
        payload["channel"] = "whatsapp"
        return None

    key = str(raw).strip().lower()
    if key not in _CHANNELS:
        return f"«{raw}» مو قناة معروفة. استخدم whatsapp أو sms."

    payload["channel"] = _CHANNELS[key]
    return None


def _missing_id_message(known_ids: set[str]) -> str:
    available = ", ".join(sorted(known_ids)) or "ما فيه مواعيد مسجّلة"
    return f"ما فيه موعد بهذا الـ id. المتاح: {available}."


def _check_tool_input(
    name: str, payload: dict[str, Any], known_ids: set[str], timezone: str
) -> str | None:
    """يرجّع رسالة خطأ للموديل، أو None لو الاستدعاء سليم."""
    if name == "create_appointment":
        if not str(payload.get("title") or "").strip():
            return "العنوان مطلوب وما ينفع يكون فاضي."
        return _normalise_at(payload, timezone)

    if name == "update_appointment":
        if payload.get("id") not in known_ids:
            return _missing_id_message(known_ids)
        if payload.get("at") is not None:
            return _normalise_at(payload, timezone)
        return None

    if name in ("delete_appointment", "complete_appointment"):
        if payload.get("id") not in known_ids:
            return _missing_id_message(known_ids)
        return None

    if name == "call_contact":
        if not str(payload.get("who") or "").strip():
            return "لازم تحدّد مين تكلّم."
        return None

    if name == "send_message":
        if not str(payload.get("who") or "").strip():
            return "لازم تحدّد مين تبعت له."
        if not str(payload.get("text") or "").strip():
            return "نص الرسالة فاضي."
        error = _normalise_channel(payload)
        if error:
            return error
        # at اختياري: null = ابعت حالًا.
        if payload.get("at") is not None:
            return _normalise_at(payload, timezone)
        return None

    return f"أداة غير معروفة: {name}"


def chat(
    *,
    message: str,
    now_iso: str,
    timezone: str,
    appointments: list[dict[str, Any]],
    history: list[dict[str, Any]],
) -> dict[str, Any]:
    """
    يشغّل لفّة محادثة واحدة.

    بيرجّع {"reply": str, "actions": list} — الأوامر اللي التطبيق ينفّذها محليًا.
    """
    provider = get_provider()
    context = build_context(
        now_iso=now_iso, timezone=timezone, appointments=appointments
    )
    known_ids = {str(a.get("id")) for a in appointments if a.get("id") is not None}

    turns: list[Turn] = [
        UserTurn(text=m["content"])
        if m["role"] == "user"
        else AssistantTurn(text=m["content"])
        for m in history[-MAX_HISTORY_MESSAGES:]
    ]
    turns.append(UserTurn(text=message))

    if settings.SEKERTER_TOOLS == "text":
        return _text_mode(
            provider, instructions=INSTRUCTIONS, context=context,
            turns=turns, known_ids=known_ids, timezone=timezone,
        )

    specs = tool_defs.tool_specs()
    actions: list[dict[str, Any]] = []

    for _ in range(MAX_TURNS):
        reply = provider.complete(
            instructions=INSTRUCTIONS,
            context=context,
            turns=turns,
            tools=specs,
        )

        if reply.refused:
            return {"reply": REFUSAL_REPLY, "actions": []}

        if not reply.tool_calls:
            return {"reply": reply.text, "actions": actions}

        turns.append(AssistantTurn(text=reply.text, tool_calls=reply.tool_calls))

        results: list[ToolResult] = []
        for call in reply.tool_calls:
            error = _check_tool_input(
                call.name, call.arguments, known_ids, timezone
            )
            if error:
                results.append(
                    ToolResult(call_id=call.id, content=error, is_error=True)
                )
                continue

            actions.append(
                {"type": tool_defs.ACTION_TYPES[call.name], **call.arguments}
            )
            results.append(
                ToolResult(call_id=call.id, content="تم، انسجّل.")
            )

        turns.append(ToolResultsTurn(results=results))

    # وصلنا لحد اللفّات من غير رد نصي. الأوامر اللي اتجمّعت صحيحة، فنرجّعها
    # مع تأكيد بسيط بدل ما نضيّعها.
    logger.warning("hit MAX_TURNS without a text reply")
    return {
        "reply": "تم، سوّيت اللي طلبته." if actions else BUSY_REPLY,
        "actions": actions,
    }


def _text_mode(
    provider,
    *,
    instructions: str,
    context: str,
    turns: list[Turn],
    known_ids: set[str],
    timezone: str,
) -> dict[str, Any]:
    """
    الأوامر بتيجي كـJSON جوّه نص الرد بدل استدعاء أدوات.

    لفّة واحدة بس — مافيش حلقة. الحلقة في الوضع العادي موجودة عشان نرجّع
    للموديل نتيجة كل أداة، وهنا مافيش أدوات يرجعلها شي. لو الموديل غلط في
    أمر، الأمر ده بس بيتشال والباقي يعدّي؛ إحنا ما نقدرش نطلب منه يصحّح من
    غير لفّة زيادة، والسكوت أحسن من إننا نعرض له خطأ تقني.
    """
    reply = provider.complete(
        instructions=instructions + text_protocol.instructions(),
        context=context,
        turns=turns,
        # الأدوات ما بتتبعتش أصلًا — السيرفر اللي بنستخدمه ما يدعمهاش،
        # وإرسالها ممكن يخلّيه يرفض الطلب كله.
        tools=[],
    )

    if reply.refused:
        return {"reply": REFUSAL_REPLY, "actions": []}

    text, calls = text_protocol.split(reply.text)

    actions: list[dict[str, Any]] = []
    for call in calls:
        error = _check_tool_input(
            call["name"], call["input"], known_ids, timezone
        )
        if error:
            logger.warning("text-mode call rejected: %s — %s", call["name"], error)
            continue
        actions.append(
            {"type": tool_defs.ACTION_TYPES[call["name"]], **call["input"]}
        )

    return {"reply": text or "تم.", "actions": actions}
