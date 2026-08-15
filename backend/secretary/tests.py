"""
اختبارات المسار كله بموديل موك.

الهدف إن منطق السيرفر (التحقق، حلقة الأدوات، تحويل الاستدعاءات لأوامر، الرفض،
الأخطاء) يبقى متغطّى من غير ما نستدعي Claude الحقيقي ولا نحتاج مفتاح.
"""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import patch

from django.test import SimpleTestCase, override_settings

CHAT_URL = "/api/secretary/chat"
AUTH = {"HTTP_AUTHORIZATION": "Bearer test-token"}

APPOINTMENTS = [
    {
        "id": "a1",
        "title": "ميعاد الدكتور",
        "at": "2026-08-16T17:30:00+03:00",
        "remind_before_minutes": 60,
        "repeat": "none",
        "notes": "",
        "done": False,
    }
]


def text_block(text: str):
    return SimpleNamespace(type="text", text=text)


def tool_block(name: str, payload: dict, block_id: str = "toolu_1"):
    return SimpleNamespace(type="tool_use", name=name, input=payload, id=block_id)


def reply(content: list, stop_reason: str = "end_turn", **extra):
    return SimpleNamespace(content=content, stop_reason=stop_reason, **extra)


class FakeMessages:
    """بيرجّع ردود محضّرة بالترتيب، وبيسجّل الطلبات عشان نفحصها."""

    def __init__(self, responses):
        self._responses = list(responses)
        self.calls = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        if not self._responses:
            raise AssertionError("الموديل اتنده مرات أكتر من المتوقع")
        return self._responses.pop(0)


def fake_client(responses):
    messages = FakeMessages(responses)
    client = SimpleNamespace(beta=SimpleNamespace(messages=messages))
    return client, messages


def post(test, payload, **extra):
    headers = {**AUTH, **extra}
    return test.client.post(
        CHAT_URL, data=payload, content_type="application/json", **headers
    )


BASE_PAYLOAD = {
    "message": "فكرني بميعاد الدكتور بكرة الساعة ٥ ونص",
    "now": "2026-08-15T14:30:00+03:00",
    "timezone": "Africa/Cairo",
    "appointments": APPOINTMENTS,
    "history": [],
}


@override_settings(
    SEKERTER_API_TOKEN="test-token", ANTHROPIC_API_KEY="test-key", DEBUG=False
)
class HealthTests(SimpleTestCase):
    def test_health_needs_no_token(self):
        response = self.client.get("/api/secretary/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})


@override_settings(
    SEKERTER_API_TOKEN="test-token", ANTHROPIC_API_KEY="test-key", DEBUG=False
)
class AuthTests(SimpleTestCase):
    def test_missing_token_is_rejected(self):
        response = self.client.post(
            CHAT_URL, data=BASE_PAYLOAD, content_type="application/json"
        )
        self.assertEqual(response.status_code, 403)

    def test_wrong_token_is_rejected(self):
        response = post(self, BASE_PAYLOAD, HTTP_AUTHORIZATION="Bearer nope")
        self.assertEqual(response.status_code, 403)

    def test_token_without_bearer_prefix_is_rejected(self):
        response = post(self, BASE_PAYLOAD, HTTP_AUTHORIZATION="test-token")
        self.assertEqual(response.status_code, 403)


@override_settings(
    SEKERTER_API_TOKEN="test-token", ANTHROPIC_API_KEY="test-key", DEBUG=False
)
class ValidationTests(SimpleTestCase):
    def test_blank_message_is_rejected(self):
        response = post(self, {**BASE_PAYLOAD, "message": "   "})
        self.assertEqual(response.status_code, 400)

    def test_missing_now_is_rejected(self):
        payload = {k: v for k, v in BASE_PAYLOAD.items() if k != "now"}
        response = post(self, payload)
        self.assertEqual(response.status_code, 400)

    def test_bad_repeat_value_is_rejected(self):
        payload = {
            **BASE_PAYLOAD,
            "appointments": [{**APPOINTMENTS[0], "repeat": "hourly"}],
        }
        response = post(self, payload)
        self.assertEqual(response.status_code, 400)


@override_settings(
    SEKERTER_API_TOKEN="test-token", ANTHROPIC_API_KEY="test-key", DEBUG=False
)
class ChatFlowTests(SimpleTestCase):
    def run_chat(self, responses, payload=None):
        client, messages = fake_client(responses)
        with patch("secretary.brain._client", return_value=client):
            response = post(self, payload or BASE_PAYLOAD)
        return response, messages

    def test_create_becomes_an_action(self):
        created = {
            "title": "ميعاد الدكتور",
            "at": "2026-08-16T17:30:00+03:00",
            "remind_before_minutes": 60,
            "repeat": "none",
            "notes": "",
        }
        response, _ = self.run_chat(
            [
                reply([tool_block("create_appointment", created)], "tool_use"),
                reply([text_block("تمام، سجّلت ميعاد الدكتور بكرة ٥:٣٠ م.")]),
            ]
        )
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(len(body["actions"]), 1)
        self.assertEqual(body["actions"][0]["type"], "create")
        self.assertEqual(body["actions"][0]["at"], created["at"])
        self.assertIn("سجّلت", body["reply"])

    def test_two_appointments_in_one_message(self):
        first = {
            "title": "اجتماع المورّد",
            "at": "2026-08-16T11:00:00+03:00",
            "remind_before_minutes": 60,
            "repeat": "none",
            "notes": "",
        }
        second = {
            "title": "تسليم الشحنة",
            "at": "2026-08-16T15:00:00+03:00",
            "remind_before_minutes": 30,
            "repeat": "none",
            "notes": "",
        }
        response, _ = self.run_chat(
            [
                reply(
                    [
                        tool_block("create_appointment", first, "t1"),
                        tool_block("create_appointment", second, "t2"),
                    ],
                    "tool_use",
                ),
                reply([text_block("سجّلت الاتنين.")]),
            ]
        )
        self.assertEqual(len(response.json()["actions"]), 2)

    def test_question_answered_without_actions(self):
        response, _ = self.run_chat(
            [reply([text_block("عندك ميعاد الدكتور بكرة الساعة ٥ ونص.")])]
        )
        body = response.json()
        self.assertEqual(body["actions"], [])
        self.assertIn("الدكتور", body["reply"])

    def test_delete_uses_known_id(self):
        response, _ = self.run_chat(
            [
                reply([tool_block("delete_appointment", {"id": "a1"})], "tool_use"),
                reply([text_block("اتلغى.")]),
            ]
        )
        actions = response.json()["actions"]
        self.assertEqual(actions, [{"type": "delete", "id": "a1"}])

    def test_unknown_id_is_sent_back_as_tool_error(self):
        response, messages = self.run_chat(
            [
                reply([tool_block("delete_appointment", {"id": "ghost"})], "tool_use"),
                reply([text_block("مش لاقي الميعاد ده.")]),
            ]
        )
        # الأمر ما اتسجّلش، والموديل اتبعتله خطأ عشان يصحّح.
        self.assertEqual(response.json()["actions"], [])
        results = messages.calls[1]["messages"][-1]["content"]
        self.assertTrue(results[0]["is_error"])
        self.assertIn("مفيش ميعاد", results[0]["content"])

    def test_bad_datetime_is_sent_back_as_tool_error(self):
        bad = {
            "title": "اجتماع",
            "at": "بكرة الساعة خمسة",
            "remind_before_minutes": 60,
            "repeat": "none",
            "notes": "",
        }
        response, messages = self.run_chat(
            [
                reply([tool_block("create_appointment", bad)], "tool_use"),
                reply([text_block("عذرًا، أعيد المحاولة.")]),
            ]
        )
        self.assertEqual(response.json()["actions"], [])
        results = messages.calls[1]["messages"][-1]["content"]
        self.assertTrue(results[0]["is_error"])
        self.assertIn("ISO 8601", results[0]["content"])

    def test_naive_datetime_is_rejected(self):
        bad = {
            "title": "اجتماع",
            "at": "2026-08-16T17:30:00",
            "remind_before_minutes": 60,
            "repeat": "none",
            "notes": "",
        }
        response, messages = self.run_chat(
            [
                reply([tool_block("create_appointment", bad)], "tool_use"),
                reply([text_block("تمام.")]),
            ]
        )
        self.assertEqual(response.json()["actions"], [])
        self.assertIn("فرق التوقيت", messages.calls[1]["messages"][-1]["content"][0]["content"])

    def test_refusal_returns_a_friendly_reply(self):
        response, _ = self.run_chat(
            [
                reply(
                    [],
                    "refusal",
                    stop_details=SimpleNamespace(category="cyber"),
                )
            ]
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["actions"], [])
        self.assertIn("مقدرتش", response.json()["reply"])

    def test_loop_stops_at_max_turns(self):
        payload = {
            "title": "اجتماع",
            "at": "2026-08-16T11:00:00+03:00",
            "remind_before_minutes": 60,
            "repeat": "none",
            "notes": "",
        }
        # موديل بيستدعي أداة كل لفّة ومبيردّش بنص أبدًا.
        looping = [
            reply([tool_block("create_appointment", payload, f"t{i}")], "tool_use")
            for i in range(10)
        ]
        response, messages = self.run_chat(looping)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(messages.calls), 4)  # MAX_TURNS

    def test_history_is_capped(self):
        history = [
            {"role": "user" if i % 2 == 0 else "assistant", "content": f"رسالة {i}"}
            for i in range(40)
        ]
        _, messages = self.run_chat(
            [reply([text_block("تمام.")])],
            payload={**BASE_PAYLOAD, "history": history},
        )
        sent = messages.calls[0]["messages"]
        self.assertEqual(len(sent), 21)  # 20 من التاريخ + الرسالة الجديدة
        self.assertEqual(sent[0]["content"], "رسالة 20")


@override_settings(
    SEKERTER_API_TOKEN="test-token", ANTHROPIC_API_KEY="test-key", DEBUG=False
)
class PromptTests(SimpleTestCase):
    def test_appointments_and_now_reach_the_model(self):
        client, messages = fake_client([reply([text_block("تمام.")])])
        with patch("secretary.brain._client", return_value=client):
            post(self, BASE_PAYLOAD)

        system = messages.calls[0]["system"]
        # البلوك الثابت الأول ومتكاش، والمتغيّر بعده — الترتيب ده بيحافظ ع الكاش.
        self.assertEqual(system[0]["cache_control"], {"type": "ephemeral"})
        self.assertNotIn("cache_control", system[1])
        self.assertIn("2026-08-15T14:30:00+03:00", system[1]["text"])
        self.assertIn("id=a1", system[1]["text"])
        self.assertIn("ميعاد الدكتور", system[1]["text"])

    def test_empty_appointments_says_so(self):
        client, messages = fake_client([reply([text_block("تمام.")])])
        with patch("secretary.brain._client", return_value=client):
            post(self, {**BASE_PAYLOAD, "appointments": []})
        self.assertIn("مفيش مواعيد مسجّلة", messages.calls[0]["system"][1]["text"])

    def test_request_uses_opus_5_and_all_tools(self):
        client, messages = fake_client([reply([text_block("تمام.")])])
        with patch("secretary.brain._client", return_value=client):
            post(self, BASE_PAYLOAD)

        call = messages.calls[0]
        self.assertEqual(call["model"], "claude-opus-5")
        self.assertEqual(
            {t["name"] for t in call["tools"]},
            {
                "create_appointment",
                "update_appointment",
                "delete_appointment",
                "complete_appointment",
            },
        )
        self.assertEqual(call["fallbacks"], "default")


@override_settings(SEKERTER_API_TOKEN="test-token", ANTHROPIC_API_KEY="", DEBUG=False)
class MissingKeyTests(SimpleTestCase):
    def test_missing_api_key_returns_503_not_500(self):
        response = post(self, BASE_PAYLOAD)
        self.assertEqual(response.status_code, 503)
        self.assertIn("ANTHROPIC_API_KEY", response.json()["detail"])
