import '../models/appointment.dart';

/// تقويم الجهاز — **لسه مو مربوط**.
///
/// السبب تعارض حقيقي في الحزم: كل نسخ `device_calendar` تعتمد على
/// `timezone ≤0.9`، بينما `flutter_local_notifications` تحتاج `^0.11`.
/// والتذكيرات المجدولة هي جوهر التطبيق فما ينفع ننزّلها، فالتقويم انشال
/// مؤقتًا بدل ما يعطّل البناء كله.
///
/// **الباقي جاهز ومختبَر**: الموعد فيه حقل [AppointmentSource]، والسيرفر
/// يعلّم أحداث التقويم «للقراءة بس» في البرومبت، والموديل متعلّم إنه ما
/// يعدّلها. لما يترجع التقويم — بقناة أصلية أو حزمة متصانة — الشغل الباقي
/// هو ملء الدالتين تحت بس.
class CalendarService {
  /// دايمًا false لحد ما التقويم يترجع.
  Future<bool> ensurePermission() async => false;

  /// أحداث التقويم في نافذة زمنية.
  ///
  /// لما تترجع، السكرتير يقدر يجاوب «أنا فاضي الخميس؟» من واقع جدوله كله
  /// مو من مواعيده اللي سجّلها بس.
  Future<List<Appointment>> eventsBetween(DateTime from, DateTime to) async =>
      const [];

  /// يضيف موعد السكرتير لتقويم الجهاز. يرجّع معرّف الحدث أو null.
  Future<String?> addEvent(Appointment appointment) async => null;

  Future<void> deleteEvent(String eventId) async {}
}
