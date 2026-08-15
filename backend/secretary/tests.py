"""
اختبارات المسار كله بمزوّد موك.

الهدف إن منطق السيرفر (التحقق، حلقة الأدوات، تحويل الاستدعاءات لأوامر، الرفض،
الأخطاء) وترجمة كل مزوّد لشكل الـAPI بتاعه يبقوا متغطّيين من غير نداءات حقيقية
ولا مفاتيح.
"""

from __future__ import annotations

import json
from types import SimpleNamespace
from unittest.mock import patch

from django.test import SimpleTestCase, override_settings

from .providers.base import (
    AssistantTurn,
    ModelReply,
    ToolCall,
    ToolResult,
    ToolResultsTurn,
    ToolSpec,
    UserTurn,
)

CHAT_URL = "/api/secretary/chat"
AUTH = {"HTTP_AUTHORIZATION": "Bearer test-token"}

APPOINTMENTS = [
    {
        "id": "a1",
        "title": "موعد الدكتور",
        "at": "2026-08-16T17:30:00+03:00",
        "remind_before_minutes": 60,
        "repeat": "none",
        "notes": "",
        "done": False,
    }
]

BASE_PAYLOAD = {
    "message": "ذكّرني بموعد الدكتور بكرة الساعة ٥ ونص",
    "now": "2026-08-15T14:30:00+03:00",
    "timezone": "Asia/Riyadh",
    "appointments": APPOINTMENTS,
    "history": [],
}

CREATE_ARGS = {
    "title": "موعد الدكتور",
    "at": "2026-08-16T17:30:00+03:00",
    "remind_before_minutes": 60,
    "repeat": "none",
    "notes": "",
}


class FakeProvider:
    """بيرجّع ردود محضّرة بالترتيب، وبيسجّل النداءات عشان نفحصها."""

    name = "fake"

    def __init__(self, replies):
        self._replies = list(replies)
        self.calls = []

    def complete(self, *, instructions, context, turns, tools):
        self.calls.append(
            {
                "instructions": instructions,
                "context": context,
                # نسخة عشان اللفّات الجاية ما تعدّلش اللي اتسجّل.
                "turns": list(turns),
                "tools": tools,
            }
        )
        if not self._replies:
            raise AssertionError("المزوّد اتنده مرات أكتر من المتوقع")
        return self._replies.pop(0)


def post(test, payload=None, **extra):
    return test.client.post(
        CHAT_URL,
        data=payload or BASE_PAYLOAD,
        content_type="application/json",
        **{**AUTH, **extra},
    )


BASE_SETTINGS = dict(
    SEKERTER_API_TOKEN="test-token",
    SEKERTER_PROVIDER="claude",
    ANTHROPIC_API_KEY="test-key",
    DEBUG=False,
)


@override_settings(**BASE_SETTINGS)
class HealthTests(SimpleTestCase):
    def test_health_needs_no_token(self):
        response = self.client.get("/api/secretary/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})


@override_settings(**BASE_SETTINGS)
class AuthTests(SimpleTestCase):
    def test_missing_token_is_rejected(self):
        response = self.client.post(
            CHAT_URL, data=BASE_PAYLOAD, content_type="application/json"
        )
        self.assertEqual(response.status_code, 403)

    def test_wrong_token_is_rejected(self):
        self.assertEqual(
            post(self, HTTP_AUTHORIZATION="Bearer nope").status_code, 403
        )

    def test_token_without_bearer_prefix_is_rejected(self):
        self.assertEqual(
            post(self, HTTP_AUTHORIZATION="test-token").status_code, 403
        )


@override_settings(**BASE_SETTINGS)
class ValidationTests(SimpleTestCase):
    def test_blank_message_is_rejected(self):
        response = post(self, {**BASE_PAYLOAD, "message": "   "})
        self.assertEqual(response.status_code, 400)

    def test_missing_now_is_rejected(self):
        payload = {k: v for k, v in BASE_PAYLOAD.items() if k != "now"}
        self.assertEqual(post(self, payload).status_code, 400)

    def test_bad_repeat_value_is_rejected(self):
        payload = {
            **BASE_PAYLOAD,
            "appointments": [{**APPOINTMENTS[0], "repeat": "hourly"}],
        }
        self.assertEqual(post(self, payload).status_code, 400)


@override_settings(**BASE_SETTINGS)
class ChatFlowTests(SimpleTestCase):
    def run_chat(self, replies, payload=None):
        provider = FakeProvider(replies)
        with patch("secretary.brain.get_provider", return_value=provider):
            response = post(self, payload)
        return response, provider

    def test_create_becomes_an_action(self):
        response, _ = self.run_chat(
            [
                ModelReply(
                    tool_calls=[ToolCall("t1", "create_appointment", CREATE_ARGS)]
                ),
                ModelReply(text="تم، سجّلت موعد الدكتور بكرة ٥:٣٠ م."),
            ]
        )
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(len(body["actions"]), 1)
        self.assertEqual(body["actions"][0]["type"], "create")
        self.assertEqual(body["actions"][0]["at"], CREATE_ARGS["at"])
        self.assertIn("سجّلت", body["reply"])

    def test_two_appointments_in_one_message(self):
        second = {**CREATE_ARGS, "title": "تسليم الشحنة"}
        response, _ = self.run_chat(
            [
                ModelReply(
                    tool_calls=[
                        ToolCall("t1", "create_appointment", CREATE_ARGS),
                        ToolCall("t2", "create_appointment", second),
                    ]
                ),
                ModelReply(text="سجّلت الاثنين."),
            ]
        )
        self.assertEqual(len(response.json()["actions"]), 2)

    def test_question_answered_without_actions(self):
        response, _ = self.run_chat(
            [ModelReply(text="عندك موعد الدكتور بكرة الساعة ٥ ونص.")]
        )
        body = response.json()
        self.assertEqual(body["actions"], [])
        self.assertIn("الدكتور", body["reply"])

    def test_delete_uses_known_id(self):
        response, _ = self.run_chat(
            [
                ModelReply(
                    tool_calls=[ToolCall("t1", "delete_appointment", {"id": "a1"})]
                ),
                ModelReply(text="انلغى."),
            ]
        )
        self.assertEqual(
            response.json()["actions"], [{"type": "delete", "id": "a1"}]
        )

    def test_unknown_id_is_sent_back_as_tool_error(self):
        response, provider = self.run_chat(
            [
                ModelReply(
                    tool_calls=[
                        ToolCall("t1", "delete_appointment", {"id": "ghost"})
                    ]
                ),
                ModelReply(text="ما لقيت هذا الموعد."),
            ]
        )
        # الأمر ما اتسجّلش، والموديل اتبعتله خطأ عشان يصحّح.
        self.assertEqual(response.json()["actions"], [])
        results = provider.calls[1]["turns"][-1].results
        self.assertTrue(results[0].is_error)
        self.assertIn("ما فيه موعد", results[0].content)

    def test_bad_datetime_is_sent_back_as_tool_error(self):
        bad = {**CREATE_ARGS, "at": "بكرة الساعة خمسة"}
        response, provider = self.run_chat(
            [
                ModelReply(
                    tool_calls=[ToolCall("t1", "create_appointment", bad)]
                ),
                ModelReply(text="معليش، أعيد المحاولة."),
            ]
        )
        self.assertEqual(response.json()["actions"], [])
        self.assertIn("ISO 8601", provider.calls[1]["turns"][-1].results[0].content)

    def test_naive_datetime_is_rejected(self):
        bad = {**CREATE_ARGS, "at": "2026-08-16T17:30:00"}
        response, provider = self.run_chat(
            [
                ModelReply(
                    tool_calls=[ToolCall("t1", "create_appointment", bad)]
                ),
                ModelReply(text="تم."),
            ]
        )
        self.assertEqual(response.json()["actions"], [])
        self.assertIn(
            "فرق التوقيت", provider.calls[1]["turns"][-1].results[0].content
        )

    def test_blank_title_is_rejected(self):
        bad = {**CREATE_ARGS, "title": "  "}
        response, provider = self.run_chat(
            [
                ModelReply(
                    tool_calls=[ToolCall("t1", "create_appointment", bad)]
                ),
                ModelReply(text="تم."),
            ]
        )
        self.assertEqual(response.json()["actions"], [])
        self.assertIn("العنوان", provider.calls[1]["turns"][-1].results[0].content)

    def test_refusal_returns_a_friendly_reply(self):
        response, _ = self.run_chat([ModelReply(refused=True)])
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["actions"], [])
        self.assertIn("ما قدرت", response.json()["reply"])

    def test_loop_stops_at_max_turns(self):
        looping = [
            ModelReply(
                tool_calls=[ToolCall(f"t{i}", "create_appointment", CREATE_ARGS)]
            )
            for i in range(10)
        ]
        response, provider = self.run_chat(looping)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(provider.calls), 4)  # MAX_TURNS

    def test_history_is_capped(self):
        history = [
            {"role": "user" if i % 2 == 0 else "assistant", "content": f"رسالة {i}"}
            for i in range(40)
        ]
        _, provider = self.run_chat(
            [ModelReply(text="تم.")],
            payload={**BASE_PAYLOAD, "history": history},
        )
        turns = provider.calls[0]["turns"]
        self.assertEqual(len(turns), 21)  # 20 من التاريخ + الرسالة الجديدة
        self.assertEqual(turns[0].text, "رسالة 20")

    def test_provider_failure_becomes_503(self):
        from .providers.base import ProviderError

        provider = FakeProvider([])
        provider.complete = lambda **_: (_ for _ in ()).throw(
            ProviderError("الخدمة مشغولة.")
        )
        with patch("secretary.brain.get_provider", return_value=provider):
            response = post(self)
        self.assertEqual(response.status_code, 503)
        self.assertIn("مشغولة", response.json()["detail"])


@override_settings(**BASE_SETTINGS)
class PromptTests(SimpleTestCase):
    def _capture(self, payload=None):
        provider = FakeProvider([ModelReply(text="تم.")])
        with patch("secretary.brain.get_provider", return_value=provider):
            post(self, payload)
        return provider.calls[0]

    def test_context_carries_now_and_appointments(self):
        call = self._capture()
        self.assertIn("2026-08-15T14:30:00+03:00", call["context"])
        self.assertIn("id=a1", call["context"])
        self.assertIn("موعد الدكتور", call["context"])
        # التعليمات منفصلة عن السياق عشان تتكاش لوحدها.
        self.assertNotIn("2026-08-15", call["instructions"])

    def test_empty_appointments_says_so(self):
        call = self._capture({**BASE_PAYLOAD, "appointments": []})
        self.assertIn("ما فيه مواعيد مسجّلة", call["context"])

    def test_all_four_tools_are_offered(self):
        call = self._capture()
        self.assertEqual(
            {t.name for t in call["tools"]},
            {
                "create_appointment",
                "update_appointment",
                "delete_appointment",
                "complete_appointment",
            },
        )


# ── ترجمة المزوّدين ────────────────────────────────────────────────────────
# الجزء ده هو أخطر جزء في الاستبدال: نفس المحادثة لازم تتحوّل صح لشكلين
# مختلفين تمامًا. الاختبارات دي بتقارن الشكل الناتج بشكل كل API.

CONVERSATION = [
    UserTurn(text="ذكّرني بالدكتور بكرة ٥"),
    AssistantTurn(
        text="ثانية وحدة",
        tool_calls=[ToolCall("t1", "create_appointment", CREATE_ARGS)],
    ),
    ToolResultsTurn(
        results=[
            ToolResult(call_id="t1", content="تم، انسجّل."),
            ToolResult(call_id="t2", content="ما فيه موعد كذا.", is_error=True),
        ]
    ),
]

SPEC = ToolSpec(
    name="create_appointment",
    description="يسجّل موعد",
    parameters={"type": "object", "properties": {}},
)


class ClaudeEncodingTests(SimpleTestCase):
    def setUp(self):
        from .providers.claude import ClaudeProvider

        self.encode = ClaudeProvider._encode
        self.encode_tool = ClaudeProvider._encode_tool

    def test_user_turn(self):
        self.assertEqual(
            self.encode(CONVERSATION[0]),
            {"role": "user", "content": "ذكّرني بالدكتور بكرة ٥"},
        )

    def test_assistant_turn_keeps_text_then_tool_use(self):
        encoded = self.encode(CONVERSATION[1])
        self.assertEqual(encoded["role"], "assistant")
        self.assertEqual(encoded["content"][0]["type"], "text")
        self.assertEqual(encoded["content"][1]["type"], "tool_use")
        self.assertEqual(encoded["content"][1]["id"], "t1")
        self.assertEqual(encoded["content"][1]["input"], CREATE_ARGS)

    def test_tool_results_collapse_into_one_user_message(self):
        encoded = self.encode(CONVERSATION[2])
        self.assertEqual(encoded["role"], "user")
        self.assertEqual(len(encoded["content"]), 2)
        self.assertEqual(encoded["content"][0]["tool_use_id"], "t1")
        # is_error بيتحط بس لما يكون True.
        self.assertNotIn("is_error", encoded["content"][0])
        self.assertTrue(encoded["content"][1]["is_error"])

    def test_tools_use_strict_input_schema(self):
        encoded = self.encode_tool(SPEC)
        self.assertTrue(encoded["strict"])
        self.assertEqual(encoded["input_schema"], SPEC.parameters)


class DeepSeekEncodingTests(SimpleTestCase):
    def setUp(self):
        from .providers.deepseek import DeepSeekProvider

        self.encode = DeepSeekProvider._encode
        self.encode_tool = DeepSeekProvider._encode_tool
        self.decode_call = DeepSeekProvider._decode_call

    def test_user_turn(self):
        self.assertEqual(
            self.encode(CONVERSATION[0]),
            [{"role": "user", "content": "ذكّرني بالدكتور بكرة ٥"}],
        )

    def test_assistant_turn_serialises_arguments_as_json(self):
        encoded = self.encode(CONVERSATION[1])[0]
        self.assertEqual(encoded["role"], "assistant")
        call = encoded["tool_calls"][0]
        self.assertEqual(call["type"], "function")
        self.assertEqual(call["function"]["name"], "create_appointment")
        self.assertEqual(json.loads(call["function"]["arguments"]), CREATE_ARGS)

    def test_tool_results_become_one_message_each(self):
        encoded = self.encode(CONVERSATION[2])
        self.assertEqual(len(encoded), 2)
        self.assertTrue(all(m["role"] == "tool" for m in encoded))
        self.assertEqual(encoded[0]["tool_call_id"], "t1")
        self.assertEqual(encoded[1]["tool_call_id"], "t2")

    def test_tools_use_openai_function_shape(self):
        encoded = self.encode_tool(SPEC)
        self.assertEqual(encoded["type"], "function")
        self.assertEqual(encoded["function"]["name"], SPEC.name)
        self.assertEqual(encoded["function"]["parameters"], SPEC.parameters)

    def test_valid_json_arguments_are_decoded(self):
        raw = SimpleNamespace(
            id="t1",
            function=SimpleNamespace(
                name="create_appointment", arguments=json.dumps(CREATE_ARGS)
            ),
        )
        call = self.decode_call(raw)
        self.assertEqual(call.arguments, CREATE_ARGS)

    def test_broken_json_arguments_are_dropped_not_raised(self):
        raw = SimpleNamespace(
            id="t1",
            function=SimpleNamespace(name="create_appointment", arguments="{ نص"),
        )
        self.assertIsNone(self.decode_call(raw))

    def test_non_object_arguments_are_dropped(self):
        raw = SimpleNamespace(
            id="t1",
            function=SimpleNamespace(name="create_appointment", arguments="[1,2]"),
        )
        self.assertIsNone(self.decode_call(raw))


class ProviderSelectionTests(SimpleTestCase):
    @override_settings(SEKERTER_PROVIDER="claude", ANTHROPIC_API_KEY="k")
    def test_claude_is_selected(self):
        from .providers import get_provider

        self.assertEqual(get_provider().name, "claude")

    @override_settings(
        SEKERTER_PROVIDER="deepseek",
        DEEPSEEK_API_KEY="k",
        DEEPSEEK_BASE_URL="",
        SEKERTER_MODEL="",
    )
    def test_deepseek_is_selected(self):
        from .providers import get_provider

        self.assertEqual(get_provider().name, "deepseek")

    @override_settings(SEKERTER_PROVIDER="gpt")
    def test_unknown_provider_raises(self):
        from .providers import ProviderError, get_provider

        with self.assertRaises(ProviderError):
            get_provider()


@override_settings(
    SEKERTER_API_TOKEN="test-token",
    SEKERTER_PROVIDER="deepseek",
    DEEPSEEK_API_KEY="",
    DEBUG=False,
)
class MissingKeyTests(SimpleTestCase):
    def test_missing_api_key_returns_503_not_500(self):
        response = post(self)
        self.assertEqual(response.status_code, 503)
        self.assertIn("DEEPSEEK_API_KEY", response.json()["detail"])
