import 'package:intl/intl.dart';

/// تنسيق التواريخ بالطريقة اللي الناس بتقولها، مش بالطريقة اللي الكمبيوتر
/// بيكتبها. «بكرة ٥:٣٠ م» أوضح من «2026-08-16 17:30» بمراحل.
class ArabicDate {
  const ArabicDate._();

  static final DateFormat _time = DateFormat('h:mm', 'ar');
  static final DateFormat _dayMonth = DateFormat('d MMMM', 'ar');
  static final DateFormat _weekday = DateFormat('EEEE', 'ar');
  static final DateFormat _full = DateFormat('EEEE d MMMM y', 'ar');

  static String time(DateTime at) => '${_time.format(at)} ${_meridiem(at)}';

  static String _meridiem(DateTime at) => at.hour < 12 ? 'ص' : 'م';

  /// «اليوم»، «بكرة»، «الخميس»، أو «٢٠ أغسطس» حسب قرب اليوم.
  static String day(DateTime at, {DateTime? now}) {
    final today = _startOfDay(now ?? DateTime.now());
    final target = _startOfDay(at);
    final days = target.difference(today).inDays;

    return switch (days) {
      0 => 'اليوم',
      1 => 'بكرة',
      2 => 'عقب بكرة',
      -1 => 'أمس',
      // جوّه الأسبوع الجاي اسم اليوم يكفي ومفيش لبس.
      > 2 && < 7 => _weekday.format(at),
      _ => _dayMonth.format(at),
    };
  }

  /// السطر الكامل اللي بيتعرض جنب الموعد.
  static String dayAndTime(DateTime at, {DateTime? now}) =>
      '${day(at, now: now)} · ${time(at)}';

  static String fullDate(DateTime at) => _full.format(at);

  /// «باقي ساعتين»، «بعد ٣ أيام»، «فات».
  static String relative(DateTime at, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    if (at.isBefore(reference)) return 'فات';

    final gap = at.difference(reference);
    if (gap.inMinutes < 1) return 'الحين';
    if (gap.inMinutes < 60) return 'باقي ${gap.inMinutes} دقيقة';
    if (gap.inHours < 24) {
      return switch (gap.inHours) {
        1 => 'باقي ساعة',
        2 => 'باقي ساعتين',
        _ => 'باقي ${gap.inHours} ساعات',
      };
    }
    return switch (gap.inDays) {
      1 => 'باقي يوم',
      2 => 'باقي يومين',
      < 11 => 'باقي ${gap.inDays} أيام',
      _ => 'باقي ${gap.inDays} يوم',
    };
  }

  /// وصف التذكير في تفاصيل الموعد.
  static String reminderLead(int minutes) {
    if (minutes <= 0) return 'التذكير في وقت الموعد';
    if (minutes < 60) return 'التذكير قبله بـ $minutes دقيقة';
    if (minutes % 60 != 0) return 'التذكير قبله بـ $minutes دقيقة';

    final hours = minutes ~/ 60;
    if (hours < 24) {
      return switch (hours) {
        1 => 'التذكير قبله بساعة',
        2 => 'التذكير قبله بساعتين',
        _ => 'التذكير قبله بـ $hours ساعات',
      };
    }
    final days = hours ~/ 24;
    return switch (days) {
      1 => 'التذكير قبله بيوم',
      2 => 'التذكير قبله بيومين',
      _ => 'التذكير قبله بـ $days أيام',
    };
  }

  static DateTime _startOfDay(DateTime at) =>
      DateTime(at.year, at.month, at.day);
}
