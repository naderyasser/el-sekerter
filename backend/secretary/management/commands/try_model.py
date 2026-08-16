"""
يجرّب الموديل الحقيقي بجُمل سعودية ويقول لك النتيجة.

الاختبارات العادية (`manage.py test secretary`) بتشتغل على عميل موك، يعني
بتتأكد إن الكود صح — مش إن الموديل شغّال. الأمر ده بيكمّل الناقص: بيبعت
كلام حقيقي لسيرفرك ويشوف يرجع بإيه.

    python manage.py try_model

الحاجة اللي بيقيسها ومحدش غيره يقدر يقيسها: هل الموديل بيرجّع **استدعاء
أداة** ولا بيرد كلام حلو وبس. لأن لو رد كلام من غير أداة، السكرتير هيقول
«أبشر» ومايتسجّلش أي موعد — وده أسوأ فشل ممكن، لأنه شكله نجاح.
"""

from __future__ import annotations

import datetime as dt

from django.conf import settings
from django.core.management.base import BaseCommand

from ...brain import chat
from ...providers import ProviderError

TIMEZONE = "Asia/Riyadh"

# كل حالة: الجملة، ونوع الأمر المتوقّع، وليه الحالة دي مهمة.
CASES = [
    (
        "عندي اجتماع مع أبو سعد بكرة الساعة خمسة العصر",
        "create",
        "تسجيل موعد بوقت صريح",
    ),
    (
        "ذكّرني أروح المستشفى بعد المغرب يوم الأحد",
        "create",
        "وقت نسبي لصلاة — الموديل لازم يحوّله لساعة",
    ),
    (
        "كلّم أبو خالد",
        "call",
        "أمر اتصال، والاسم يرجع زي ما هو",
    ),
    (
        "ابعت لسعد على الواتس قل له تأخرت شوي",
        "message",
        "رسالة واتس، ولازم يفصل الاسم عن النص",
    ),
    (
        "وش عندي بكرة؟",
        None,
        "سؤال — لازم يرد كلام من غير ما يسجّل شي",
    ),
]


class Command(BaseCommand):
    help = "يجرّب الموديل الحقيقي بجُمل سعودية"

    def handle(self, *args, **options):
        now = dt.datetime.now(dt.timezone(dt.timedelta(hours=3)))

        self.stdout.write("")
        self.stdout.write(f"  العنوان : {self._url()}")
        self.stdout.write(f"  الصيغة  : {self._format()}")
        self.stdout.write(f"  الموديل : {settings.SEKERTER_MODEL or '(الافتراضي)'}")
        self.stdout.write(f"  الأوامر : {settings.SEKERTER_TOOLS}")
        self.stdout.write("")

        passed = 0

        for sentence, expected, why in CASES:
            self.stdout.write(f"  ‹ {sentence}")

            try:
                result = chat(
                    message=sentence,
                    now_iso=now.isoformat(),
                    timezone=TIMEZONE,
                    appointments=[],
                    history=[],
                )
            except ProviderError as exc:
                self.stdout.write(self.style.ERROR(f"    ما وصلت للموديل: {exc}"))
                self.stdout.write("")
                self._unreachable()
                return

            actions = result["actions"]
            got = actions[0]["type"] if actions else None

            self.stdout.write(f"  › {result['reply']}")

            if got == expected:
                passed += 1
                self.stdout.write(self.style.SUCCESS(f"    تمام — {why}"))
                for action in actions:
                    self.stdout.write(f"    {action}")
            elif expected is None:
                self.stdout.write(
                    self.style.WARNING(
                        f"    سجّل «{got}» والمفروض ما يسجّل شي — {why}"
                    )
                )
            elif got is None:
                self.stdout.write(
                    self.style.ERROR(
                        f"    رد كلام بس وما استدعى أداة — {why}"
                    )
                )
            else:
                self.stdout.write(
                    self.style.ERROR(f"    طلع «{got}» والمتوقّع «{expected}»")
                )

            self.stdout.write("")

        self._verdict(passed)

    def _url(self) -> str:
        if settings.SEKERTER_BASE_URL:
            return settings.SEKERTER_BASE_URL
        if settings.SEKERTER_PROVIDER == "claude":
            return settings.ANTHROPIC_BASE_URL or "https://api.anthropic.com"
        return settings.DEEPSEEK_BASE_URL or "https://api.deepseek.com"

    def _format(self) -> str:
        if settings.SEKERTER_BASE_URL:
            return settings.SEKERTER_FORMAT
        return "messages" if settings.SEKERTER_PROVIDER == "claude" else "chat"

    def _key_name(self) -> str:
        if settings.SEKERTER_BASE_URL:
            return "SEKERTER_API_KEY"
        return (
            "ANTHROPIC_API_KEY"
            if settings.SEKERTER_PROVIDER == "claude"
            else "DEEPSEEK_API_KEY"
        )

    def _unreachable(self) -> None:
        """فشل اتصال — مو فشل موديل. الفرق مهم عشان ما تدوّر في المكان الغلط."""
        other = "chat" if self._format() == "messages" else "messages"
        self.stdout.write(
            self.style.ERROR(
                "  ما فيه اتصال بالموديل — المشكلة في العنوان أو المفتاح أو\n"
                "  الصيغة، مو في الموديل نفسه. تأكد من:\n"
                f"    • السيرفر شغّال فعلًا على {self._url()}\n"
                "    • الجهاز اللي عليه Django يوصل للعنوان ده\n"
                f"    • {self._key_name()} هو مفتاح سيرفرك\n"
                f"    • لو الرد ٤٠٤، جرّب SEKERTER_FORMAT={other}"
            )
        )
        self.stdout.write("")

    def _verdict(self, passed: int) -> None:
        total = len(CASES)
        self.stdout.write(f"  نجح {passed} من {total}")

        if passed == total:
            self.stdout.write(
                self.style.SUCCESS("  الموديل جاهز — ركّب التطبيق وكلّمه.")
            )
        elif settings.SEKERTER_TOOLS == "text":
            self.stdout.write(
                self.style.WARNING(
                    "  الوضع النصّي شغّال بس الموديل مو ملتزم بالبروتوكول في كل\n"
                    "  الحالات. جرّب موديل أكبر من اللي يخدمه سيرفرك."
                )
            )
        elif passed <= 1:
            self.stdout.write(
                self.style.ERROR(
                    "  سيرفرك ما يمرّر الأدوات — يرد كلام عدل بس ما ينفّذ شي.\n"
                    "  ده أخطر وضع، لأن السكرتير يبان شغّال وما يسجّل ولا موعد.\n"
                    "\n"
                    "  الحل: حط في .env\n"
                    "      SEKERTER_TOOLS=text\n"
                    "  وأعد تشغيل الأمر. الأوامر بتيجي كـJSON جوّه نص الرد بدل\n"
                    "  استدعاء الأدوات، وده يشتغل على أي سيرفر."
                )
            )
        else:
            self.stdout.write(
                self.style.WARNING(
                    "  يستدعي أدوات بس مو في كل الحالات. غالبًا موديل صغير.\n"
                    "  جرّب واحد أكبر، أو حط SEKERTER_TOOLS=text وقارن."
                )
            )
        self.stdout.write("")
