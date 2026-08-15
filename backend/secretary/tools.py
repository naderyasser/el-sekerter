"""
الأدوات اللي الموديل بيستدعيها.

مهم: السيرفر **مش** بينفّذ الأدوات دي — هو بيسجّلها كأوامر ويرجّعها للتطبيق،
والتطبيق هو اللي ينفّذها على قاعدة البيانات المحلية بتاعته ويجدول الإشعارات.
عشان كده مفيش `list_appointments`: التطبيق بيبعت المواعيد الحالية مع كل رسالة،
فالموديل بيقراها من البرومبت على طول من غير لفة زيادة.
"""

REPEAT_VALUES = ["none", "daily", "weekly", "monthly", "yearly"]

_DATETIME_DESC = (
    "وقت الميعاد بصيغة ISO 8601 ومعاه فرق التوقيت، "
    "زي 2026-08-16T17:30:00+03:00. لازم يكون في المستقبل بالنسبة للوقت الحالي."
)

_REMIND_DESC = (
    "التذكير بيرنّ قبل الميعاد بكام دقيقة. 60 هو الافتراضي لو المستخدم مقالش. "
    "استخدم 0 لو عايزه يرنّ في وقت الميعاد بالظبط."
)


def _nullable(schema: dict, description: str) -> dict:
    """حقل اختياري في التعديل: null معناها «سيبه زي ما هو»."""
    return {"anyOf": [schema, {"type": "null"}], "description": description}


CREATE_APPOINTMENT = {
    "name": "create_appointment",
    "description": (
        "يسجّل ميعاد جديد ويجدول تذكير بيه. استخدمها لما صاحب العمل يقول عن "
        "حاجة هيعملها في وقت معيّن، أو يطلب تفكيره بحاجة."
    ),
    "strict": True,
    "input_schema": {
        "type": "object",
        "properties": {
            "title": {
                "type": "string",
                "description": (
                    "عنوان قصير للميعاد بلغة صاحب العمل، زي «ميعاد الدكتور» أو "
                    "«اجتماع المورّد». من غير كلمات زي «فكرني» أو «متنساش»."
                ),
            },
            "at": {"type": "string", "description": _DATETIME_DESC},
            "remind_before_minutes": {"type": "integer", "description": _REMIND_DESC},
            "repeat": {
                "type": "string",
                "enum": REPEAT_VALUES,
                "description": "تكرار الميعاد. none للميعاد اللي مرة واحدة.",
            },
            "notes": {
                "type": "string",
                "description": (
                    "أي تفاصيل زيادة قالها صاحب العمل (مكان، رقم تليفون، "
                    "حاجة يجيبها معاه). سيبها فاضية لو مفيش."
                ),
            },
        },
        "required": ["title", "at", "remind_before_minutes", "repeat", "notes"],
        "additionalProperties": False,
    },
}

UPDATE_APPOINTMENT = {
    "name": "update_appointment",
    "description": (
        "يعدّل ميعاد موجود. حط null في أي حقل مش عايز تغيّره. "
        "الـ id لازم يكون واحد من المواعيد المذكورة في «مواعيده الحالية»."
    ),
    "strict": True,
    "input_schema": {
        "type": "object",
        "properties": {
            "id": {"type": "string", "description": "معرّف الميعاد المراد تعديله."},
            "title": _nullable({"type": "string"}, "العنوان الجديد، أو null."),
            "at": _nullable({"type": "string"}, f"{_DATETIME_DESC} أو null."),
            "remind_before_minutes": _nullable(
                {"type": "integer"}, f"{_REMIND_DESC} أو null."
            ),
            "repeat": _nullable(
                {"type": "string", "enum": REPEAT_VALUES}, "التكرار الجديد، أو null."
            ),
            "notes": _nullable({"type": "string"}, "الملاحظات الجديدة، أو null."),
        },
        "required": ["id", "title", "at", "remind_before_minutes", "repeat", "notes"],
        "additionalProperties": False,
    },
}

DELETE_APPOINTMENT = {
    "name": "delete_appointment",
    "description": (
        "يلغي ميعاد خالص. استخدمها لما صاحب العمل يقول إن الميعاد اتلغى أو "
        "يطلب مسحه. لو الميعاد حصل خلاص استخدم complete_appointment بدالها."
    ),
    "strict": True,
    "input_schema": {
        "type": "object",
        "properties": {
            "id": {"type": "string", "description": "معرّف الميعاد المراد إلغاؤه."},
        },
        "required": ["id"],
        "additionalProperties": False,
    },
}

COMPLETE_APPOINTMENT = {
    "name": "complete_appointment",
    "description": (
        "يعلّم الميعاد إنه خلص. استخدمها لما صاحب العمل يقول إنه راح أو عمل "
        "الحاجة دي بالفعل."
    ),
    "strict": True,
    "input_schema": {
        "type": "object",
        "properties": {
            "id": {"type": "string", "description": "معرّف الميعاد اللي خلص."},
        },
        "required": ["id"],
        "additionalProperties": False,
    },
}

ALL_TOOLS = [
    CREATE_APPOINTMENT,
    UPDATE_APPOINTMENT,
    DELETE_APPOINTMENT,
    COMPLETE_APPOINTMENT,
]

TOOL_NAMES = {tool["name"] for tool in ALL_TOOLS}

# الأمر اللي بيتبعت للتطبيق لكل استدعاء أداة. الأسماء متطابقة عشان التطبيق
# يـswitch عليها على طول من غير جدول تحويل.
ACTION_TYPES = {
    "create_appointment": "create",
    "update_appointment": "update",
    "delete_appointment": "delete",
    "complete_appointment": "complete",
}
