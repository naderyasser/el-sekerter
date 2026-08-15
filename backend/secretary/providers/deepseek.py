"""
مزوّد DeepSeek.

الـAPI بتاعهم متوافق مع OpenAI، فبنستخدم مكتبة openai وبنغيّر base_url بس.

فروق عن Claude تستاهل الانتباه:
  • مفيش تكاش للبرومبت بنفس الشكل، فالتعليمات والسياق بيتلزقوا في رسالة
    system واحدة.
  • مفيش تبليغ صريح عن رفض المصنّفات — الرفض بيجي كنص عادي.
  • نتايج الأدوات بتتبعت رسالة لكل نتيجة (role="tool")، مش رسالة واحدة.
  • الوسائط بتوصل نص JSON محتاج تحليل، مش dict جاهز.
"""

from __future__ import annotations

import json
import logging
from typing import Any

from django.conf import settings
from openai import APIConnectionError, APIStatusError, OpenAI

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

DEFAULT_BASE_URL = "https://api.deepseek.com"
DEFAULT_MODEL = "deepseek-chat"
MAX_TOKENS = 4096


class DeepSeekProvider:
    name = "deepseek"

    def __init__(self, *, api_key: str, model: str = "", base_url: str = ""):
        if not api_key:
            raise ProviderError("DEEPSEEK_API_KEY مو مضبوط على السيرفر.")
        self._client = OpenAI(
            api_key=api_key, base_url=base_url or DEFAULT_BASE_URL
        )
        self._model = model or DEFAULT_MODEL

    def complete(
        self,
        *,
        instructions: str,
        context: str,
        turns: list[Turn],
        tools: list[ToolSpec],
    ) -> ModelReply:
        messages: list[dict[str, Any]] = [
            {"role": "system", "content": f"{instructions}\n\n{context}"}
        ]
        for turn in turns:
            messages.extend(self._encode(turn))

        try:
            response = self._client.chat.completions.create(
                model=self._model,
                max_tokens=MAX_TOKENS,
                messages=messages,
                tools=[self._encode_tool(tool) for tool in tools],
                # درجة حرارة واطية: ده استخراج تواريخ مش كتابة إبداعية.
                temperature=0.2,
            )
        except APIStatusError as exc:
            logger.warning("DeepSeek API error %s", exc.status_code)
            raise ProviderError("الخدمة مشغولة الحين، جرّب مرة ثانية بعد شوي.") from exc
        except APIConnectionError as exc:
            logger.warning("DeepSeek connection error: %s", exc)
            raise ProviderError("ما أقدر أوصل لخدمة الذكاء الاصطناعي.") from exc

        if not response.choices:
            raise ProviderError("الخدمة رجّعت رد فاضي.")

        message = response.choices[0].message

        return ModelReply(
            text=(message.content or "").strip(),
            tool_calls=[
                call
                for call in (
                    self._decode_call(raw) for raw in (message.tool_calls or [])
                )
                if call is not None
            ],
        )

    @staticmethod
    def _decode_call(raw: Any) -> ToolCall | None:
        """
        بيحلّل وسائط الاستدعاء.

        الوسائط بتيجي نص JSON من الموديل، فممكن تكون بايظة. استدعاء بايظ
        بيتتجاهل ويترد عليه بنص عادي أحسن من إن الطلب كله يقع.
        """
        try:
            arguments = json.loads(raw.function.arguments or "{}")
        except (json.JSONDecodeError, AttributeError):
            logger.warning("tool arguments were not valid JSON: %r", raw)
            return None
        if not isinstance(arguments, dict):
            return None
        return ToolCall(id=raw.id, name=raw.function.name, arguments=arguments)

    @staticmethod
    def _encode_tool(tool: ToolSpec) -> dict[str, Any]:
        return {
            "type": "function",
            "function": {
                "name": tool.name,
                "description": tool.description,
                "parameters": tool.parameters,
            },
        }

    @staticmethod
    def _encode(turn: Turn) -> list[dict[str, Any]]:
        match turn:
            case UserTurn(text=text):
                return [{"role": "user", "content": text}]

            case AssistantTurn(text=text, tool_calls=calls):
                message: dict[str, Any] = {
                    "role": "assistant",
                    "content": text or None,
                }
                if calls:
                    message["tool_calls"] = [
                        {
                            "id": call.id,
                            "type": "function",
                            "function": {
                                "name": call.name,
                                "arguments": json.dumps(
                                    call.arguments, ensure_ascii=False
                                ),
                            },
                        }
                        for call in calls
                    ]
                return [message]

            case ToolResultsTurn(results=results):
                # رسالة منفصلة لكل نتيجة — عكس Anthropic اللي بيجمّعهم.
                return [
                    {
                        "role": "tool",
                        "tool_call_id": r.call_id,
                        "content": r.content,
                    }
                    for r in results
                ]

        raise AssertionError(f"نوع دور غير معروف: {turn!r}")


def build() -> DeepSeekProvider:
    return DeepSeekProvider(
        api_key=settings.DEEPSEEK_API_KEY,
        model=settings.SEKERTER_MODEL,
        base_url=settings.DEEPSEEK_BASE_URL,
    )
