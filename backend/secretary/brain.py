"""
استدعاء Claude وحلقة الأدوات.

السيرفر ما بينفّذش الأدوات — بيسجّلها كأوامر ويرجّع للموديل «تمام» عشان يكمّل
كلامه، والتطبيق هو اللي ينفّذها فعليًا على قاعدة البيانات المحلية. عشان كده
حلقة الأدوات هنا مصطنعة بالكامل ومحدودة بعدد لفّات صغير.
"""

from __future__ import annotations

import datetime as dt
import logging
from typing import Any

import anthropic
from django.conf import settings

from . import tools as tool_defs
from .prompt import build_system

logger = logging.getLogger(__name__)

MODEL = "claude-opus-5"
MAX_TOKENS = 4096

# حد أمان للحلقة. رسالة عادية بتخلص في لفّة أو اتنين؛ اللي بيوصل لـ4 غالبًا
# موديل بيلف حوالين نفسه، وأحسن نوقفه بدل ما نفضل ندفع.
MAX_TURNS = 4

# آخر كام رسالة من التاريخ بتتبعت. بيحدّ التكلفة ويخلّي السياق مركّز.
MAX_HISTORY_MESSAGES = 20

FALLBACK_BETA = "server-side-fallback-2026-07-01"

BUSY_REPLY = "الخدمة مشغولة دلوقتي، جرّب تاني بعد شوية."
REFUSAL_REPLY = "معلش، مقدرتش أتعامل مع الطلب ده. ممكن تقوله بطريقة تانية؟"


class BrainUnavailable(RuntimeError):
    """الموديل مش متاح دلوقتي — رسالة للمستخدم مش تتبيعة stack."""


def _client() -> anthropic.Anthropic:
    if not settings.ANTHROPIC_API_KEY:
        raise BrainUnavailable("ANTHROPIC_API_KEY مش متظبّط على السيرفر.")
    return anthropic.Anthropic(api_key=settings.ANTHROPIC_API_KEY)


def _validate_at(value: Any) -> str | None:
    """يتأكد إن الوقت اللي طلعه الموديل ISO 8601 صالح ومعاه فرق توقيت."""
    if not isinstance(value, str):
        return "الوقت لازم يكون نص بصيغة ISO 8601."
    try:
        parsed = dt.datetime.fromisoformat(value)
    except ValueError:
        return f"«{value}» مش صيغة ISO 8601 صالحة. المطلوب زي 2026-08-16T17:30:00+03:00."
    if parsed.tzinfo is None:
        return f"«{value}» ناقصه فرق التوقيت. زوّد +03:00 مثلًا."
    return None


def _check_tool_input(name: str, payload: dict[str, Any], known_ids: set[str]) -> str | None:
    """يرجّع رسالة خطأ للموديل، أو None لو الاستدعاء سليم."""
    if name == "create_appointment":
        return _validate_at(payload.get("at"))

    if name == "update_appointment":
        if payload.get("id") not in known_ids:
            return (
                f"مفيش ميعاد بالـ id ده. المتاح: "
                f"{', '.join(sorted(known_ids)) or 'مفيش مواعيد مسجّلة'}."
            )
        if payload.get("at") is not None:
            return _validate_at(payload.get("at"))
        return None

    if name in ("delete_appointment", "complete_appointment"):
        if payload.get("id") not in known_ids:
            return (
                f"مفيش ميعاد بالـ id ده. المتاح: "
                f"{', '.join(sorted(known_ids)) or 'مفيش مواعيد مسجّلة'}."
            )
        return None

    return f"أداة غير معروفة: {name}"


def _extract_text(content: list[Any]) -> str:
    return "\n".join(b.text for b in content if b.type == "text").strip()


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
    client = _client()
    system = build_system(
        now_iso=now_iso, timezone=timezone, appointments=appointments
    )
    known_ids = {str(a.get("id")) for a in appointments if a.get("id") is not None}

    messages: list[dict[str, Any]] = [
        {"role": m["role"], "content": m["content"]}
        for m in history[-MAX_HISTORY_MESSAGES:]
    ]
    messages.append({"role": "user", "content": message})

    actions: list[dict[str, Any]] = []

    for _ in range(MAX_TURNS):
        try:
            response = client.beta.messages.create(
                model=MODEL,
                max_tokens=MAX_TOKENS,
                system=system,
                messages=messages,
                tools=tool_defs.ALL_TOOLS,
                output_config={"effort": settings.SEKERTER_EFFORT},
                # لو مصنّفات الأمان رفضت الطلب، الـAPI بيعيده على موديل تاني
                # في نفس النداء بدل ما يرجّع رفض.
                betas=[FALLBACK_BETA],
                fallbacks="default",
            )
        except anthropic.APIStatusError as exc:
            logger.warning("Claude API error %s: %s", exc.status_code, exc.message)
            raise BrainUnavailable(BUSY_REPLY) from exc
        except anthropic.APIConnectionError as exc:
            logger.warning("Claude connection error: %s", exc)
            raise BrainUnavailable(BUSY_REPLY) from exc

        # لازم قبل قراءة content: الرفض بيرجّع 200 بمحتوى فاضي أو ناقص.
        if response.stop_reason == "refusal":
            logger.info(
                "refusal: %s",
                getattr(response.stop_details, "category", None),
            )
            return {"reply": REFUSAL_REPLY, "actions": []}

        tool_uses = [b for b in response.content if b.type == "tool_use"]

        if not tool_uses:
            return {
                "reply": _extract_text(response.content),
                "actions": actions,
            }

        messages.append({"role": "assistant", "content": response.content})

        results: list[dict[str, Any]] = []
        for block in tool_uses:
            payload = dict(block.input)
            error = _check_tool_input(block.name, payload, known_ids)
            if error:
                results.append(
                    {
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": error,
                        "is_error": True,
                    }
                )
                continue

            actions.append(
                {"type": tool_defs.ACTION_TYPES[block.name], **payload}
            )
            results.append(
                {
                    "type": "tool_result",
                    "tool_use_id": block.id,
                    "content": "تمام، اتسجّل.",
                }
            )

        messages.append({"role": "user", "content": results})

    # وصلنا لحد اللفّات من غير رد نصي. الأوامر اللي اتجمّعت صحيحة، فنرجّعها
    # مع تأكيد بسيط بدل ما نضيّعها.
    logger.warning("hit MAX_TURNS without a text reply")
    return {
        "reply": "تمام، عملت اللي طلبته." if actions else BUSY_REPLY,
        "actions": actions,
    }
