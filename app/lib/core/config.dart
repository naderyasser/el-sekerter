/// ثوابت التطبيق.
class AppConfig {
  const AppConfig._();

  static const String appName = 'السكرتير الخاص';

  /// عنوان السيرفر. يتغيّر وقت البناء:
  ///   flutter build apk --dart-define=API_BASE_URL=https://example.com
  /// وكمان قابل للتعديل من شاشة الإعدادات وقت التشغيل.
  static const String defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const Duration connectTimeout = Duration(seconds: 10);

  /// الرد بيستنى الموديل يفكّر ويرد، فالمهلة أطول من المعتاد.
  static const Duration receiveTimeout = Duration(seconds: 90);

  /// التذكير الافتراضي لو المستخدم مقالش.
  static const int defaultRemindBeforeMinutes = 60;

  /// سقف الإشعارات المجدولة **على آيفون بس**.
  ///
  /// أبل بتحدّد ٦٤ إشعار مجدول لكل تطبيق وبترمي الزيادة بصمت، فبنجدول أقرب
  /// [maxScheduledIos] وبنسيب الباقي فسحة لملخصات الصبح (٧ كحد أقصى).
  /// بنعيد الجدولة كل ما التطبيق يفتح، فالمواعيد البعيدة بتدخل النافذة
  /// أول ما القريبة تعدّي.
  static const int maxScheduledIos = 50;

  /// سقف الإشعارات المجدولة على أندرويد.
  ///
  /// أندرويد **مافيهوش** حد زي بتاع أبل، والرقم ده سقف أمان ضد بيانات
  /// بايظة مش حد حقيقي. تطبيق الرقم الآيفوني (٥٠) على أندرويد كان أخطر
  /// باج في التطبيق: كل موعد بياخد إشعارين (تذكير مسبق + صفّارة)، يعني
  /// ٥٠ إشعار = **٢٥ موعد بس**. اللي بعدهم كان بيتحفظ ويتعرض في القايمة
  /// و**ما يرنّش أبدًا، في صمت كامل** — بالظبط شكوى «بحط ميعاد مش بيرن».
  static const int maxScheduledAndroid = 400;

  /// آخر كام رسالة بتتبعت للسيرفر كسياق. لازم تساوي MAX_HISTORY_MESSAGES
  /// في backend/secretary/brain.py وإلا هيتقص مرتين.
  static const int historyWindow = 20;

  /// مفاتيح التخزين
  static const String kApiBaseUrl = 'api_base_url';
  static const String kApiToken = 'api_token';

  /// قناة إشعارات أندرويد.
  ///
  /// v2 لأن أندرويد بيجمّد إعدادات القناة بعد إنشائها: النسخة الأولى كانت
  /// بصوت الإشعارات العادي، وده بيتكتم مع الوضع الصامت وعدم الإزعاج —
  /// والتذكير اللي ما يرنّش والجوال صامت هو بالظبط الحالة اللي التطبيق
  /// موجود عشانها. القناة الجديدة بتطلع الصوت من قناة المنبّه (alarm stream)
  /// اللي بيعدّي الاتنين. القديمة بتتمسح في initialize.
  static const String reminderChannelId = 'appointment_reminders_v2';
  static const String legacyReminderChannelId = 'appointment_reminders';
  static const String reminderChannelName = 'تذكير المواعيد';
  static const String reminderChannelDescription =
      'التنبيه اللي يرنّ قبل الموعد';

  /// قناة صفّارة وقت الموعد نفسه — منفصلة عن قناة التذكير لأن أندرويد
  /// بيجمّد صوت القناة بعد إنشائها: صوت الصفّارة (res/raw/siren) لازم
  /// قناة جديدة. بتشتغل على مجرى المنبّه فبترنّ حتى مع الصامت وعدم الإزعاج.
  static const String alarmChannelId = 'meeting_alarms_v1';
  static const String alarmChannelName = 'صفّارة وقت الموعد';
  static const String alarmChannelDescription =
      'إنذار قوي يرنّ في وقت الموعد نفسه';
}
