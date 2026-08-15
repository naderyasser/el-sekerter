"""
الأدوات اللي الموديل بيستدعيها.

مهم: السيرفر **مش** بينفّذ الأدوات دي — هو بيسجّلها كأوامر ويرجّعها للتطبيق،
والتطبيق هو اللي ينفّذها على قاعدة البيانات المحلية بتاعته ويجدول الإشعارات.
عشان كده مفيش `list_appointments`: التطبيق بيبعت المواعيد الحالية مع كل رسالة،
فالموديل بيقراها من البرومبت على طول من غير لفة زيادة.
"""

from .providers.base import ToolSpec

REPEAT_VALUES = ["none", "daily", "weekly", "monthly", "yearly"]

_DATETIME_DESC = (
    "وقت الموعد بصيغة ISO 8601 ومعه فرق التوقيت، "
    "زي 2026-08-16T17:30:00+03:00. لازم يكون في المستقبل بالنسبة للوقت الحالي."
)

_REMIND_DESC = (
    "التذكير يرنّ قبل الموعد بكم دقيقة. 60 هو الافتراضي إذا المستخدم ما حدّد. "
    "استخدم 0 إذا تبيه يرنّ في وقت الموعد بالضبط."
)


def _nullable(schema: dict, description: str) -> dict:
    """حقل اختياري في التعديل: null معناها «سيبه زي ما هو»."""
    return {"anyOf": [schema, {"type": "null"}], "description": description}


CREATE_APPOINTMENT = {
    "name": "create_appointment",
    "description": (
        "يسجّل موعد جديد ويجدول تذكير فيه. استخدمها لما صاحب العمل يذكر "
        "شي بيسوّيه في وقت معيّن، أو يطلب تذكيره بشي."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "title": {
                "type": "string",
                "description": (
                    "عنوان قصير للموعد بكلام صاحب العمل، مثل «موعد الدكتور» أو "
                    "«اجتماع المورّد». بدون كلمات مثل «ذكّرني» أو «لا تنسى»."
                ),
            },
            "at": {"type": "string", "description": _DATETIME_DESC},
            "remind_before_minutes": {"type": "integer", "description": _REMIND_DESC},
            "repeat": {
                "type": "string",
                "enum": REPEAT_VALUES,
                "description": "تكرار الموعد. none للموعد اللي مرة وحدة.",
            },
            "notes": {
                "type": "string",
                "description": (
                    "أي تفاصيل زيادة قالها صاحب العمل (مكان، رقم جوال، "
                    "شي يجيبه معه). خلّها فاضية إذا ما فيه."
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
        "يعدّل موعد موجود. حط null في أي حقل ما تبي تغيّره. "
        "الـ id لازم يكون واحد من المواعيد المذكورة في «مواعيده الحالية»."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "id": {"type": "string", "description": "معرّف الموعد المراد تعديله."},
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
        "يلغي الموعد نهائيًا. استخدمها لما صاحب العمل يقول إن الموعد انلغى أو "
        "يطلب حذفه. إذا الموعد صار خلاص استخدم complete_appointment بدالها."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "id": {"type": "string", "description": "معرّف الموعد المراد إلغاؤه."},
        },
        "required": ["id"],
        "additionalProperties": False,
    },
}

COMPLETE_APPOINTMENT = {
    "name": "complete_appointment",
    "description": (
        "يعلّم الموعد إنه خلص. استخدمها لما صاحب العمل يقول إنه راح أو سوّى "
        "الشي هذا فعلًا."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "id": {"type": "string", "description": "معرّف الموعد اللي خلص."},
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


def tool_specs() -> list[ToolSpec]:
    """التعريفات بالشكل المحايد اللي المزوّدين بيترجموه."""
    return [
        ToolSpec(
            name=tool["name"],
            description=tool["description"],
            parameters=tool["parameters"],
        )
        for tool in ALL_TOOLS
    ]
