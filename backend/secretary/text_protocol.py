"""
الأوامر كـJSON جوّه نص الرد، لما السيرفر ما يدعمش استدعاء الأدوات.

**ليه ده موجود أصلًا**

بعض السيرفرات بتستقبل `tools` في الطلب وترميها في صمت — خصوصًا اللي قدّامها
واجهة جلسات محادثة مش API حقيقي. النتيجة أسوأ فشل ممكن: الموديل يفهم كلامك
صح ويرد «أبشر، سجّلته» و**ما يتسجّل ولا موعد**. الفشل ده شكله نجاح، فيعدّي
من غير ما حد ياخد باله.

الحل هنا إن الأوامر تتكتب كنص جوّه الرد. أي سيرفر يقدر يطلّع نص، فالطريقة
دي بتشتغل على أي حاجة.

**الثمن الحقيقي**

أقل دقة من الأدوات الحقيقية: مافيش سكيما بتتفرض على الموديل، فممكن ينسى حقل
أو يطلّع JSON مكسور. عشان كده كل أمر بيعدّي على نفس التحقق اللي في brain.py،
والأمر اللي ما يعديش بيتشال لوحده والباقي يكمّل. لو سيرفرك بيدعم الأدوات
فعلًا، سيب SEKERTER_TOOLS=native — أدق.
"""

from __future__ import annotations

import json
import logging
import re
from typing import Any

from . import tools as tool_defs

logger = logging.getLogger(__name__)

# بلوك مسيّج باسم صريح. الاسم ده مقصود إنه نادر عشان ما يتلغبطش مع أي JSON
# تاني الموديل ممكن يكتبه في كلامه (زي ما يشرح شكل رسالة مثلًا).
FENCE = "sekerter"

# العلامة نفسها، بباك-تيكس أو من غيرها.
#
# التزمّت هنا غالي: لو الموديل كتب الأوامر صح ونسي الباك-تيكس، البلوك
# ما يتقراش و**يتعرض لصاحب العمل كـJSON خام**. وده أسوأ من ضياع الأمر —
# ضياع الأمر بيبان في السلوك، أما JSON في نص الرد فبيخلّي التطبيق كله
# يبان مكسور. حصل فعلًا في أول تشغيل حقيقي.
_MARK = re.compile(r"`{0,3}\s*" + FENCE + r"\s*`{0,3}", re.IGNORECASE)


def instructions() -> str:
    """الجزء اللي بيتزاد على البرومبت في الوضع النصّي."""
    lines = [
        "",
        "# تنفيذ الأوامر",
        "",
        "أنت ما تقدر تسوي شي بنفسك. عشان أي شي يتنفّذ فعلًا لازم تكتب بلوك",
        "أوامر في آخر ردّك بالشكل هذا بالضبط:",
        "",
        "```" + FENCE,
        '[{"tool": "اسم_الأداة", "input": { … }}]',
        "```",
        "",
        "قواعد ما تنكسر:",
        "",
        "- الكلام العادي فوق البلوك، والبلوك آخر شي في الرد.",
        "- البلوك JSON صالح: مصفوفة، ولو ما فيه أوامر لا تكتب البلوك أصلًا.",
        "- **لا تقول إنك سويت شي إلا والبلوك مكتوب.** لو قلت «أبشر، سجّلته»",
        "  وما كتبت البلوك، ما راح ينسجّل ولا شي وصاحب العمل راح يفوته موعده.",
        "- لا تشرح البلوك ولا تذكره في كلامك؛ صاحب العمل ما يشوفه.",
        "",
        "الأدوات المتاحة وحقولها:",
        "",
    ]

    for tool in tool_defs.ALL_TOOLS:
        lines.append(f"## {tool['name']}")
        lines.append(tool["description"])
        schema = tool["parameters"]
        lines.append("الحقول:")
        for field, spec in schema["properties"].items():
            desc = spec.get("description", "")
            optional = "anyOf" in spec
            note = " (ينفع null)" if optional else ""
            lines.append(f"- {field}{note}: {desc}")
        lines.append("")

    lines.extend(
        [
            "مثال كامل — «ذكّرني بالدكتور بكرة ٥ العصر»:",
            "",
            "أبشر، سجّلته لك بكرة ٥ العصر وأذكّرك قبله بساعة.",
            "```" + FENCE,
            '[{"tool": "create_appointment", "input": {"title": "موعد الدكتور",',
            ' "at": "2026-08-17T17:00:00+03:00", "remind_before_minutes": 60,',
            ' "repeat": "none", "notes": ""}}]',
            "```",
        ]
    )

    return "\n".join(lines)


def split(reply: str) -> tuple[str, list[dict[str, Any]]]:
    """
    يفصل كلام صاحب العمل عن الأوامر.

    يرجّع (النص اللي يتعرض، الاستدعاءات). أي بلوك مكسور بيتشال من النص
    ويترمى — أحسن من إننا نعرض JSON لصاحب العمل.
    """
    calls: list[dict[str, Any]] = []
    spans: list[tuple[int, int]] = []

    for mark in _MARK.finditer(reply):
        span = _json_after(reply, mark.end())
        if span is None:
            continue

        start, end = span
        body = reply[start:end]
        # الباك-تيكس اللي بتقفل السياج، لو موجودة.
        closing = re.compile(r"\s*`{1,3}").match(reply, end)
        spans.append((mark.start(), closing.end() if closing else end))

        try:
            parsed = json.loads(body)
        except ValueError:
            logger.warning("text-mode block was not valid JSON: %r", body[:200])
            continue

        # مصفوفة هي الشكل المطلوب، لكن أمر واحد لوحده غلطة شائعة نقبلها.
        if isinstance(parsed, dict):
            parsed = [parsed]
        if not isinstance(parsed, list):
            logger.warning("text-mode block was not a list: %r", body[:200])
            continue

        for item in parsed:
            call = _read_call(item)
            if call is not None:
                calls.append(call)

    text = reply
    # من الآخر للأول عشان المواضع ما تتزحلقش.
    for start, end in reversed(spans):
        text = text[:start] + text[end:]

    return text.strip(), calls


def _json_after(text: str, index: int) -> tuple[int, int] | None:
    """
    يلقّط قيمة JSON كاملة بعد الموضع ده بعدّ الأقواس.

    عدّ الأقواس بدل regex عشان البلوك ينقرا سواء اتقفل بسياج ولا لأ —
    الموديل بينسى الباك-تيكس، وساعتها مافيش علامة نهاية نلزق عندها.
    """
    while index < len(text) and text[index] in " \t\r\n":
        index += 1
    if index >= len(text) or text[index] not in "[{":
        return None

    opening = text[index]
    closing = "]" if opening == "[" else "}"
    depth = 0
    in_string = False
    escaped = False

    for position in range(index, len(text)):
        char = text[position]

        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue

        if char == '"':
            in_string = True
        elif char == opening:
            depth += 1
        elif char == closing:
            depth -= 1
            if depth == 0:
                return index, position + 1

    # ما اتقفلش — الرد اتقطع في النص. نرجّع الباقي كله عشان يتشال من
    # النص المعروض على الأقل، حتى لو التحليل هيفشل.
    return index, len(text)


def _read_call(item: Any) -> dict[str, Any] | None:
    """يتأكد إن العنصر استدعاء أداة معروف. الغلط بيتشال لوحده."""
    if not isinstance(item, dict):
        return None

    name = item.get("tool")
    if name not in tool_defs.TOOL_NAMES:
        logger.warning("text-mode call named an unknown tool: %r", name)
        return None

    payload = item.get("input")
    if payload is None:
        payload = {}
    if not isinstance(payload, dict):
        logger.warning("text-mode call had non-object input: %r", payload)
        return None

    return {"name": name, "input": payload}
