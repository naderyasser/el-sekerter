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
    # لازم يتصفّر صراحة. من غيره، .env بتاع السيرفر الحقيقي يتحمّل جوّه
    # الاختبار ويقلب اختيار المزوّد — فتفشل اختبارات سليمة على السيرفر
    # وتنجح على جهاز فاضي. اختبار يعتمد على البيئة اللي حواليه ما يثبت شي.
    SEKERTER_BASE_URL="",
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

    def test_urls_match_what_the_app_calls(self):
        """
        العناوين متكتوبة نصًا في التطبيق (api_client.dart) وفي التوثيق،
        وأي تغيير هنا يكسر الاتنين بصمت — الموبايل يرجّع 404 والمستخدم
        يشوف «الخدمة مش شغالة» من غير أي أثر في اللوج.

        الشرطة في الآخر فرق حقيقي: Django بيرجّع 404 معاها.
        """
        from django.urls import reverse

        self.assertEqual(reverse("health"), "/api/secretary/health")
        self.assertEqual(reverse("chat"), "/api/secretary/chat")
        self.assertEqual(self.client.get("/api/secretary/health/").status_code, 404)


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

    def test_call_becomes_an_action(self):
        response, _ = self.run_chat(
            [
                ModelReply(
                    tool_calls=[ToolCall("t1", "call_contact", {"who": "أبو سعد"})]
                ),
                ModelReply(text="أطلبه لك الحين."),
            ]
        )
        self.assertEqual(
            response.json()["actions"], [{"type": "call", "who": "أبو سعد"}]
        )

    def test_message_now_has_null_at(self):
        payload = {
            "who": "أبو سعد",
            "channel": "whatsapp",
            "text": "السلام عليكم، الاجتماع بكرة الساعة عشر.",
            "at": None,
        }
        response, _ = self.run_chat(
            [
                ModelReply(tool_calls=[ToolCall("t1", "send_message", payload)]),
                ModelReply(text="انبعتت."),
            ]
        )
        action = response.json()["actions"][0]
        self.assertEqual(action["type"], "message")
        self.assertEqual(action["channel"], "whatsapp")
        self.assertIsNone(action["at"])

    def test_scheduled_message_keeps_its_time(self):
        payload = {
            "who": "0501234567",
            "channel": "sms",
            "text": "تذكير بالموعد.",
            "at": "2026-08-16T09:00:00+03:00",
        }
        response, _ = self.run_chat(
            [
                ModelReply(tool_calls=[ToolCall("t1", "send_message", payload)]),
                ModelReply(text="بأبعتها بكرة الصبح."),
            ]
        )
        self.assertEqual(
            response.json()["actions"][0]["at"], "2026-08-16T09:00:00+03:00"
        )

    def test_message_without_text_is_rejected(self):
        payload = {"who": "أبو سعد", "channel": "whatsapp", "text": "  ", "at": None}
        response, provider = self.run_chat(
            [
                ModelReply(tool_calls=[ToolCall("t1", "send_message", payload)]),
                ModelReply(text="تم."),
            ]
        )
        self.assertEqual(response.json()["actions"], [])
        self.assertIn("فاضي", provider.calls[1]["turns"][-1].results[0].content)

    def test_call_without_who_is_rejected(self):
        response, provider = self.run_chat(
            [
                ModelReply(tool_calls=[ToolCall("t1", "call_contact", {"who": ""})]),
                ModelReply(text="تم."),
            ]
        )
        self.assertEqual(response.json()["actions"], [])
        self.assertIn("مين", provider.calls[1]["turns"][-1].results[0].content)

    def test_scheduled_message_with_bad_time_is_rejected(self):
        payload = {
            "who": "أبو سعد",
            "channel": "whatsapp",
            "text": "تذكير",
            "at": "بكرة الصبح",
        }
        response, provider = self.run_chat(
            [
                ModelReply(tool_calls=[ToolCall("t1", "send_message", payload)]),
                ModelReply(text="تم."),
            ]
        )
        self.assertEqual(response.json()["actions"], [])
        self.assertIn("ISO 8601", provider.calls[1]["turns"][-1].results[0].content)

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

    def test_calendar_events_are_marked_read_only(self):
        call = self._capture({
            **BASE_PAYLOAD,
            "appointments": [
                {**APPOINTMENTS[0], "id": "c1", "source": "calendar"},
            ],
        })
        self.assertIn("للقراءة بس", call["context"])

    def test_empty_appointments_says_so(self):
        call = self._capture({**BASE_PAYLOAD, "appointments": []})
        self.assertIn("ما فيه مواعيد مسجّلة", call["context"])

    def test_every_tool_is_offered(self):
        call = self._capture()
        self.assertEqual(
            {t.name for t in call["tools"]},
            {
                "create_appointment",
                "update_appointment",
                "delete_appointment",
                "complete_appointment",
                "call_contact",
                "send_message",
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
        # _encode_tool شكله بيختلف بين أنثروبيك والبوابة، فمحتاج نسخة.
        native = ClaudeProvider.__new__(ClaudeProvider)
        native._native = True
        self.encode_tool = native._encode_tool

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


@override_settings(SEKERTER_BASE_URL="")
class ProviderSelectionTests(SimpleTestCase):
    """المسار القديم: اتصال مباشر بمزوّد سحابي، من غير عنوان مخصّص."""

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


class BaseUrlSelectionTests(SimpleTestCase):
    """
    الطريقة اللي المفروض الواحد يستخدمها: عنوان ومفتاح، من غير أسماء شركات.

    اللي يهم هنا إن العنوان لما يتحط يكون هو الحاكم — لو SEKERTER_PROVIDER
    القديم فضل مأثّر، الطلب يروح لسيرفر تاني خالص من غير ما حد ياخد باله.
    """

    URL = "https://example.invalid"

    @override_settings(
        SEKERTER_BASE_URL=URL,
        SEKERTER_API_KEY="k",
        SEKERTER_FORMAT="messages",
        SEKERTER_MODEL="deepseek-chat",
    )
    def test_messages_format_builds_messages_provider(self):
        from .providers import get_provider

        provider = get_provider()
        self.assertEqual(provider.name, "claude")
        self.assertFalse(provider._native)
        self.assertEqual(provider._model, "deepseek-chat")

    @override_settings(
        SEKERTER_BASE_URL=URL,
        SEKERTER_API_KEY="k",
        SEKERTER_FORMAT="chat",
        SEKERTER_MODEL="my-model",
    )
    def test_chat_format_builds_chat_provider(self):
        from .providers import get_provider

        provider = get_provider()
        self.assertEqual(provider.name, "deepseek")
        self.assertEqual(provider._model, "my-model")

    @override_settings(
        SEKERTER_BASE_URL=URL,
        SEKERTER_API_KEY="k",
        SEKERTER_FORMAT="messages",
        SEKERTER_MODEL="",
        # المسار القديم مضبوط على حاجة تانية — لازم العنوان يكسبه.
        SEKERTER_PROVIDER="deepseek",
        DEEPSEEK_API_KEY="other",
    )
    def test_base_url_wins_over_legacy_provider(self):
        from .providers import get_provider

        self.assertEqual(get_provider().name, "claude")

    @override_settings(
        SEKERTER_BASE_URL=URL, SEKERTER_API_KEY="k", SEKERTER_FORMAT="grpc"
    )
    def test_unknown_format_raises(self):
        from .providers import ProviderError, get_provider

        with self.assertRaises(ProviderError):
            get_provider()

    @override_settings(
        SEKERTER_BASE_URL=URL, SEKERTER_API_KEY="", SEKERTER_FORMAT="messages"
    )
    def test_missing_key_names_the_right_variable(self):
        from .providers import ProviderError, get_provider

        with self.assertRaises(ProviderError) as caught:
            get_provider()
        self.assertIn("SEKERTER_API_KEY", str(caught.exception))

    @override_settings(
        SEKERTER_BASE_URL="",
        SEKERTER_PROVIDER="claude",
        ANTHROPIC_API_KEY="k",
        ANTHROPIC_BASE_URL="",
        SEKERTER_MODEL="",
    )
    def test_no_base_url_falls_back_to_direct_cloud(self):
        from .providers import get_provider

        self.assertTrue(get_provider()._native)


@override_settings(
    SEKERTER_API_TOKEN="test-token",
    SEKERTER_BASE_URL="",
    SEKERTER_PROVIDER="deepseek",
    DEEPSEEK_API_KEY="",
    DEBUG=False,
)
class MissingKeyTests(SimpleTestCase):
    def test_missing_api_key_returns_503_not_500(self):
        response = post(self)
        self.assertEqual(response.status_code, 503)
        self.assertIn("DEEPSEEK_API_KEY", response.json()["detail"])


# ── قراءة رد المزوّد ───────────────────────────────────────────────────────
# تحليل الرد هو الجزء اللي ما تغطّاش لحد دلوقتي، وهو أخطر جزء بعد الترجمة:
# غلطة هنا معناها أمر ضايع بصمت أو تطبيق بيقع.


class FakeMessages:
    """يرجّع ردود محضّرة ويسجّل الطلبات عشان نفحص شكل النداء."""

    def __init__(self, responses):
        self._responses = list(responses)
        self.calls = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        if not self._responses:
            raise AssertionError("المزوّد اتنده مرات أكتر من المتوقع")
        return self._responses.pop(0)


def anthropic_response(blocks, stop_reason="end_turn", **extra):
    return SimpleNamespace(content=blocks, stop_reason=stop_reason, **extra)


class ClaudeResponseTests(SimpleTestCase):
    """يبني ClaudeProvider بعميل موك ويقرا الرد."""

    def provider_returning(self, response):
        from .providers.claude import ClaudeProvider

        provider = ClaudeProvider.__new__(ClaudeProvider)
        provider._model = "claude-opus-5"
        provider._effort = "low"
        provider._native = True
        recorder = FakeMessages([response])
        provider._client = SimpleNamespace(
            beta=SimpleNamespace(messages=recorder)
        )
        return provider, recorder

    def complete(self, provider):
        return provider.complete(
            instructions="تعليمات", context="سياق", turns=[], tools=[SPEC]
        )

    def test_text_only_reply(self):
        provider, _ = self.provider_returning(
            anthropic_response(
                [SimpleNamespace(type="text", text="عندك موعدين بكرة.")]
            )
        )
        reply = self.complete(provider)
        self.assertEqual(reply.text, "عندك موعدين بكرة.")
        self.assertEqual(reply.tool_calls, [])
        self.assertFalse(reply.refused)

    def test_tool_call_is_read(self):
        provider, _ = self.provider_returning(
            anthropic_response(
                [
                    SimpleNamespace(type="text", text="ثانية"),
                    SimpleNamespace(
                        type="tool_use",
                        id="toolu_1",
                        name="create_appointment",
                        input=CREATE_ARGS,
                    ),
                ],
                stop_reason="tool_use",
            )
        )
        reply = self.complete(provider)
        self.assertEqual(reply.text, "ثانية")
        self.assertEqual(reply.tool_calls[0].name, "create_appointment")
        self.assertEqual(reply.tool_calls[0].arguments, CREATE_ARGS)

    def test_several_text_blocks_are_joined(self):
        provider, _ = self.provider_returning(
            anthropic_response(
                [
                    SimpleNamespace(type="text", text="الأول"),
                    SimpleNamespace(type="text", text="الثاني"),
                ]
            )
        )
        self.assertEqual(self.complete(provider).text, "الأول\nالثاني")

    def test_thinking_blocks_are_ignored(self):
        provider, _ = self.provider_returning(
            anthropic_response(
                [
                    SimpleNamespace(type="thinking", thinking="…"),
                    SimpleNamespace(type="text", text="تم."),
                ]
            )
        )
        self.assertEqual(self.complete(provider).text, "تم.")

    def test_refusal_is_flagged_and_content_untouched(self):
        # المحتوى فاضي في الرفض — قراءته من غير فحص stop_reason توقّع.
        provider, _ = self.provider_returning(
            anthropic_response(
                [],
                stop_reason="refusal",
                stop_details=SimpleNamespace(category="cyber"),
            )
        )
        reply = self.complete(provider)
        self.assertTrue(reply.refused)
        self.assertEqual(reply.tool_calls, [])

    def test_request_carries_cached_instructions_then_context(self):
        provider, recorder = self.provider_returning(
            anthropic_response([SimpleNamespace(type="text", text="تم.")])
        )
        self.complete(provider)
        system = recorder.calls[0]["system"]
        self.assertEqual(system[0]["text"], "تعليمات")
        self.assertEqual(system[0]["cache_control"], {"type": "ephemeral"})
        self.assertEqual(system[1]["text"], "سياق")
        self.assertNotIn("cache_control", system[1])


class GatewayTests(SimpleTestCase):
    """
    نفس المزوّد لكن على بوابة متوافقة بدل أنثروبيك نفسها.

    الخطر هنا إن إضافات أنثروبيك (تكاش، output_config، fallbacks، strict)
    تتسرّب للبوابة فترفض الطلب كله — والنتيجة سكرتير ما يرد على أي رسالة.
    """

    def provider_returning(self, response):
        from .providers.claude import ClaudeProvider

        provider = ClaudeProvider.__new__(ClaudeProvider)
        provider._model = "deepseek-chat"
        provider._effort = "low"
        provider._native = False
        recorder = FakeMessages([response])
        # البوابة ما عندهاش beta — لو الكود ناداه هيوقع، وده المطلوب.
        provider._client = SimpleNamespace(messages=recorder)
        return provider, recorder

    def request_for(self, response=None):
        provider, recorder = self.provider_returning(
            response or anthropic_response([SimpleNamespace(type="text", text="تم.")])
        )
        provider.complete(
            instructions="تعليمات", context="سياق", turns=[], tools=[SPEC]
        )
        return recorder.calls[0]

    def test_anthropic_only_fields_are_not_sent(self):
        request = self.request_for()
        for field in ("output_config", "betas", "fallbacks"):
            self.assertNotIn(field, request)

    def test_system_is_one_plain_string(self):
        # بلوكات مع cache_control ترفضها البوابة؛ نص واحد كل حاجة تفهمه.
        system = self.request_for()["system"]
        self.assertIsInstance(system, str)
        self.assertIn("تعليمات", system)
        self.assertIn("سياق", system)

    def test_tools_have_no_strict_flag(self):
        tool = self.request_for()["tools"][0]
        self.assertNotIn("strict", tool)
        # الباقي لازم يفضل زي ما هو وإلا الأداة ما تشتغلش.
        self.assertEqual(tool["name"], SPEC.name)
        self.assertEqual(tool["input_schema"], SPEC.parameters)

    def test_model_and_messages_still_sent(self):
        request = self.request_for()
        self.assertEqual(request["model"], "deepseek-chat")
        self.assertIn("messages", request)
        self.assertIn("max_tokens", request)

    def test_tool_call_from_gateway_is_read(self):
        request_response = anthropic_response(
            [
                SimpleNamespace(
                    type="tool_use",
                    id="toolu_1",
                    name="create_appointment",
                    input=CREATE_ARGS,
                )
            ],
            stop_reason="tool_use",
        )
        provider, _ = self.provider_returning(request_response)
        reply = provider.complete(
            instructions="تعليمات", context="سياق", turns=[], tools=[SPEC]
        )
        self.assertEqual(reply.tool_calls[0].name, "create_appointment")

    def test_refusal_without_stop_details_does_not_crash(self):
        # أنثروبيك بترجّع stop_details؛ البوابة غالبًا لأ.
        response = anthropic_response([], stop_reason="refusal")
        self.assertFalse(hasattr(response, "stop_details"))
        provider, _ = self.provider_returning(response)
        reply = provider.complete(
            instructions="تعليمات", context="سياق", turns=[], tools=[SPEC]
        )
        self.assertTrue(reply.refused)

    def test_base_url_picks_gateway_defaults(self):
        from .providers.claude import DEFAULT_GATEWAY_MODEL, ClaudeProvider

        provider = ClaudeProvider(
            api_key="k", base_url="https://example.invalid"
        )
        self.assertFalse(provider._native)
        self.assertEqual(provider._model, DEFAULT_GATEWAY_MODEL)

    def test_no_base_url_stays_on_anthropic(self):
        from .providers.claude import DEFAULT_MODEL, ClaudeProvider

        provider = ClaudeProvider(api_key="k")
        self.assertTrue(provider._native)
        self.assertEqual(provider._model, DEFAULT_MODEL)

    def test_explicit_model_wins_over_gateway_default(self):
        from .providers.claude import ClaudeProvider

        provider = ClaudeProvider(
            api_key="k",
            model="deepseek-reasoner",
            base_url="https://example.invalid",
        )
        self.assertEqual(provider._model, "deepseek-reasoner")


class DeepSeekResponseTests(SimpleTestCase):
    def provider_returning(self, message):
        from .providers.deepseek import DeepSeekProvider

        provider = DeepSeekProvider.__new__(DeepSeekProvider)
        provider._model = "deepseek-chat"
        recorder = FakeMessages(
            [SimpleNamespace(choices=[SimpleNamespace(message=message)])]
        )
        provider._client = SimpleNamespace(
            chat=SimpleNamespace(completions=recorder)
        )
        return provider, recorder

    def complete(self, provider):
        return provider.complete(
            instructions="تعليمات", context="سياق", turns=[], tools=[SPEC]
        )

    def test_text_only_reply(self):
        provider, _ = self.provider_returning(
            SimpleNamespace(content="عندك موعدين بكرة.", tool_calls=None)
        )
        reply = self.complete(provider)
        self.assertEqual(reply.text, "عندك موعدين بكرة.")
        self.assertEqual(reply.tool_calls, [])

    def test_null_content_becomes_empty_not_crash(self):
        # OpenAI بترجّع content=None لما يكون فيه استدعاء أداة بس.
        provider, _ = self.provider_returning(
            SimpleNamespace(
                content=None,
                tool_calls=[
                    SimpleNamespace(
                        id="t1",
                        function=SimpleNamespace(
                            name="create_appointment",
                            arguments=json.dumps(CREATE_ARGS),
                        ),
                    )
                ],
            )
        )
        reply = self.complete(provider)
        self.assertEqual(reply.text, "")
        self.assertEqual(reply.tool_calls[0].arguments, CREATE_ARGS)

    def test_broken_arguments_drop_only_that_call(self):
        provider, _ = self.provider_returning(
            SimpleNamespace(
                content="",
                tool_calls=[
                    SimpleNamespace(
                        id="t1",
                        function=SimpleNamespace(
                            name="create_appointment", arguments="{ مكسور"
                        ),
                    ),
                    SimpleNamespace(
                        id="t2",
                        function=SimpleNamespace(
                            name="delete_appointment",
                            arguments=json.dumps({"id": "a1"}),
                        ),
                    ),
                ],
            )
        )
        reply = self.complete(provider)
        # الاستدعاء السليم لازم يعدّي حتى لو اللي قبله بايظ.
        self.assertEqual(len(reply.tool_calls), 1)
        self.assertEqual(reply.tool_calls[0].name, "delete_appointment")

    def test_empty_choices_raises_provider_error(self):
        from .providers.base import ProviderError
        from .providers.deepseek import DeepSeekProvider

        provider = DeepSeekProvider.__new__(DeepSeekProvider)
        provider._model = "deepseek-chat"
        provider._client = SimpleNamespace(
            chat=SimpleNamespace(
                completions=FakeMessages([SimpleNamespace(choices=[])])
            )
        )
        with self.assertRaises(ProviderError):
            self.complete(provider)

    def test_instructions_and_context_merge_into_one_system_message(self):
        provider, recorder = self.provider_returning(
            SimpleNamespace(content="تم.", tool_calls=None)
        )
        self.complete(provider)
        messages = recorder.calls[0]["messages"]
        self.assertEqual(messages[0]["role"], "system")
        self.assertIn("تعليمات", messages[0]["content"])
        self.assertIn("سياق", messages[0]["content"])


class PromptContentTests(SimpleTestCase):
    """البرومبت هو اللي بيحدد سلوك السكرتير — تغيير فيه بالغلط يغيّر المنتج."""

    def test_saudi_dialect_markers_are_present(self):
        from .prompt import INSTRUCTIONS

        for marker in ["العامية السعودية", "أبشر", "الحين"]:
            self.assertIn(marker, INSTRUCTIONS)

    def test_prayer_times_and_weekend_are_covered(self):
        from .prompt import INSTRUCTIONS

        for marker in ["بعد العصر", "بعد المغرب", "الجمعة والسبت"]:
            self.assertIn(marker, INSTRUCTIONS)

    def test_model_is_told_not_to_invent_ids_or_numbers(self):
        from .prompt import INSTRUCTIONS

        self.assertIn("لا تخترع id", INSTRUCTIONS)
        self.assertIn("لا تخترع رقم", INSTRUCTIONS)

    def test_calendar_events_are_declared_read_only(self):
        from .prompt import INSTRUCTIONS

        self.assertIn("لا تعدّلها ولا تلغيها", INSTRUCTIONS)
