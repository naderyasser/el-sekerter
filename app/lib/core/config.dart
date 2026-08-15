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

  /// آيفون بيحدّد ٦٤ إشعار مجدول لكل تطبيق، وبيرمي الزيادة بصمت. بنجدول أقرب
  /// [maxScheduledReminders] بس وبنعيد الجدولة كل ما التطبيق يفتح أو المواعيد
  /// تتغيّر. الرقم أقل من ٦٤ عشان يسيب فسحة لتذكيرات التكرار.
  static const int maxScheduledReminders = 50;

  /// آخر كام رسالة بتتبعت للسيرفر كسياق. لازم تساوي MAX_HISTORY_MESSAGES
  /// في backend/secretary/brain.py وإلا هيتقص مرتين.
  static const int historyWindow = 20;

  /// مفاتيح التخزين
  static const String kApiBaseUrl = 'api_base_url';
  static const String kApiToken = 'api_token';

  /// قناة إشعارات أندرويد
  static const String reminderChannelId = 'appointment_reminders';
  static const String reminderChannelName = 'تذكير المواعيد';
  static const String reminderChannelDescription =
      'التنبيه اللي يرنّ قبل الموعد';
}
