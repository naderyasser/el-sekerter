"""التحقق من شكل الطلب الجاي من التطبيق."""

from rest_framework import serializers

from .tools import REPEAT_VALUES


class AppointmentSerializer(serializers.Serializer):
    """ميعاد زي ما التطبيق مخزّنه محليًا. بيتبعت كسياق مش كبيانات تتخزّن."""

    id = serializers.CharField(max_length=64)
    title = serializers.CharField(max_length=200, allow_blank=True)
    at = serializers.CharField(max_length=64)
    remind_before_minutes = serializers.IntegerField(
        required=False, min_value=0, max_value=60 * 24 * 30
    )
    repeat = serializers.ChoiceField(choices=REPEAT_VALUES, required=False)
    notes = serializers.CharField(
        max_length=1000, required=False, allow_blank=True
    )
    done = serializers.BooleanField(required=False)


class HistoryMessageSerializer(serializers.Serializer):
    role = serializers.ChoiceField(choices=["user", "assistant"])
    content = serializers.CharField(max_length=4000, allow_blank=True)


class ChatRequestSerializer(serializers.Serializer):
    message = serializers.CharField(max_length=2000, trim_whitespace=True)
    # وقت الجهاز — هو المرجع لأي كلام نسبي زي «بكرة». السيرفر بيثق فيه عن قصد
    # عشان التوقيت اللي يهم هو توقيت صاحب العمل مش توقيت السيرفر.
    now = serializers.CharField(max_length=64)
    timezone = serializers.CharField(max_length=64, default="Africa/Cairo")
    appointments = AppointmentSerializer(many=True, required=False, default=list)
    history = HistoryMessageSerializer(many=True, required=False, default=list)

    def validate_message(self, value: str) -> str:
        if not value.strip():
            raise serializers.ValidationError("الرسالة فاضية.")
        return value

    def validate_appointments(self, value: list) -> list:
        # حد أعلى عشان ما نبعتش سياق ضخم للموديل من غير قصد.
        if len(value) > 200:
            raise serializers.ValidationError("عدد المواعيد المبعوتة كبير جدًا.")
        return value
