"""مزوّد Claude (Anthropic)."""

from __future__ import annotations

import logging
from typing import Any

import anthropic
from django.conf import settings

from .base import (
    AssistantTurn,
    ModelReply,
    ProviderError,
    ToolCall,
    ToolResultsTurn,
    ToolSpec,
    Turn,
    UserTurn,
)

logger = logging.getLogger(__name__)

DEFAULT_MODEL = "claude-opus-5"
MAX_TOKENS = 4096
FALLBACK_BETA = "server-side-fallback-2026-07-01"


class ClaudeProvider:
    name = "claude"

    def __init__(self, *, api_key: str, model: str = "", effort: str = "low"):
        if not api_key:
            raise ProviderError("ANTHROPIC_API_KEY مو مضبوط على السيرفر.")
        self._client = anthropic.Anthropic(api_key=api_key)
        self._model = model or DEFAULT_MODEL
        self._effort = effort

    def complete(
        self,
        *,
        instructions: str,
        context: str,
        turns: list[Turn],
        tools: list[ToolSpec],
    ) -> ModelReply:
        try:
            response = self._client.beta.messages.create(
                model=self._model,
                max_tokens=MAX_TOKENS,
                system=[
                    {
                        # الحد الأدنى للتكاش على claude-opus-5 هو ٥١٢ توكن،
                        # والتعليمات فوقيه، فالبلوك ده بيتكاش ويتقرا بعد كده.
                        "type": "text",
                        "text": instructions,
                        "cache_control": {"type": "ephemeral"},
                    },
                    {"type": "text", "text": context},
                ],
                messages=[self._encode(turn) for turn in turns],
                tools=[self._encode_tool(tool) for tool in tools],
                output_config={"effort": self._effort},
                # لو مصنّفات الأمان رفضت، الـAPI بيعيد الطلب على موديل تاني في
                # نفس النداء بدل ما يرجّع رفض.
                betas=[FALLBACK_BETA],
                fallbacks="default",
            )
        except anthropic.APIStatusError as exc:
            logger.warning("Claude API error %s: %s", exc.status_code, exc.message)
            raise ProviderError("الخدمة مشغولة الحين، جرّب مرة ثانية بعد شوي.") from exc
        except anthropic.APIConnectionError as exc:
            logger.warning("Claude connection error: %s", exc)
            raise ProviderError("ما أقدر أوصل لخدمة الذكاء الاصطناعي.") from exc

        # لازم قبل قراءة content: الرفض بيرجّع 200 بمحتوى فاضي أو ناقص.
        if response.stop_reason == "refusal":
            logger.info(
                "refusal: %s", getattr(response.stop_details, "category", None)
            )
            return ModelReply(refused=True)

        return ModelReply(
            text="\n".join(
                b.text for b in response.content if b.type == "text"
            ).strip(),
            tool_calls=[
                ToolCall(id=b.id, name=b.name, arguments=dict(b.input))
                for b in response.content
                if b.type == "tool_use"
            ],
        )

    @staticmethod
    def _encode_tool(tool: ToolSpec) -> dict[str, Any]:
        return {
            "name": tool.name,
            "description": tool.description,
            # strict بيضمن إن الحقول تطابق السكيما بالظبط، فبنستغنى عن تحقق
            # دفاعي كتير في brain.py.
            "strict": True,
            "input_schema": tool.parameters,
        }

    @staticmethod
    def _encode(turn: Turn) -> dict[str, Any]:
        match turn:
            case UserTurn(text=text):
                return {"role": "user", "content": text}

            case AssistantTurn(text=text, tool_calls=calls):
                content: list[dict[str, Any]] = []
                if text:
                    content.append({"type": "text", "text": text})
                content.extend(
                    {
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.name,
                        "input": call.arguments,
                    }
                    for call in calls
                )
                return {"role": "assistant", "content": content}

            case ToolResultsTurn(results=results):
                # في Anthropic نتايج الأدوات بتيجي كلها في رسالة user واحدة.
                return {
                    "role": "user",
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": r.call_id,
                            "content": r.content,
                            **({"is_error": True} if r.is_error else {}),
                        }
                        for r in results
                    ],
                }

        raise AssertionError(f"نوع دور غير معروف: {turn!r}")


def build() -> ClaudeProvider:
    return ClaudeProvider(
        api_key=settings.ANTHROPIC_API_KEY,
        model=settings.SEKERTER_MODEL,
        effort=settings.SEKERTER_EFFORT,
    )
