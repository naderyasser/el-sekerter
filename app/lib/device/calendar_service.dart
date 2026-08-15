import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/appointment.dart';

/// تقويم الجهاز.
///
/// السكرتير يكتب مواعيده في التقويم الحقيقي عشان يشوفها مع باقي حياته، ويقرا
/// اللي فيه عشان يقدر يجاوب «أنا فاضي الخميس؟» من واقع جدوله مو من مواعيده
/// اللي سجّلها بس.
///
/// أحداث التقويم اللي ما سجّلها السكرتير تُقرأ ولا تُعدّل — البرومبت يعلّمها
/// «للقراءة بس» والموديل ما يستدعي عليها أدوات التعديل.
class CalendarService {
  CalendarService([DeviceCalendarPlugin? plugin])
    : _plugin = plugin ?? DeviceCalendarPlugin();

  final DeviceCalendarPlugin _plugin;

  Calendar? _target;

  Future<bool> ensurePermission() async {
    final granted = await _plugin.hasPermissions();
    if (granted.isSuccess && (granted.data ?? false)) return true;
    final requested = await _plugin.requestPermissions();
    return requested.isSuccess && (requested.data ?? false);
  }

  /// التقويم اللي بنكتب فيه: أول تقويم افتراضي قابل للكتابة.
  Future<Calendar?> _writableCalendar() async {
    if (_target != null) return _target;

    final result = await _plugin.retrieveCalendars();
    final calendars = result.data;
    if (calendars == null || calendars.isEmpty) return null;

    final writable = calendars.where((c) => !(c.isReadOnly ?? true));
    if (writable.isEmpty) return null;

    _target = writable.firstWhere(
      (c) => c.isDefault ?? false,
      orElse: () => writable.first,
    );
    return _target;
  }

  /// أحداث التقويم في نافذة زمنية، بشكل [Appointment] عشان تندمج مع مواعيد
  /// السكرتير في نفس القايمة وفي البرومبت.
  Future<List<Appointment>> eventsBetween(DateTime from, DateTime to) async {
    if (!await ensurePermission()) return const [];

    final result = await _plugin.retrieveCalendars();
    final calendars = result.data ?? [];
    final events = <Appointment>[];

    for (final calendar in calendars) {
      final id = calendar.id;
      if (id == null) continue;

      final found = await _plugin.retrieveEvents(
        id,
        RetrieveEventsParams(startDate: from, endDate: to),
      );

      for (final event in found.data ?? <Event>[]) {
        final start = event.start;
        if (start == null || event.eventId == null) continue;
        events.add(
          Appointment(
            // بادئة عشان ما يتلخبطش مع id مواعيد السكرتير.
            id: 'cal:${event.eventId}',
            title: event.title ?? 'حدث',
            at: DateTime(
              start.year,
              start.month,
              start.day,
              start.hour,
              start.minute,
            ),
            notes: event.description ?? '',
            source: AppointmentSource.calendar,
          ),
        );
      }
    }

    events.sort((a, b) => a.at.compareTo(b.at));
    return events;
  }

  /// يضيف موعد السكرتير للتقويم. يرجّع معرّف الحدث عشان نقدر نعدّله أو نمسحه
  /// بعدين، أو null لو ما نجح.
  Future<String?> addEvent(Appointment appointment) async {
    if (!await ensurePermission()) return null;

    final calendar = await _writableCalendar();
    if (calendar == null) return null;

    // tz.local اتظبّطت في ReminderScheduler.initialize قبل أول إطار.
    final location = tz.local;
    final event = Event(
      calendar.id,
      title: appointment.title,
      description: appointment.notes,
      start: tz.TZDateTime.from(appointment.at, location),
      // مدة افتراضية ساعة: التقويمات ما تحب أحداث بلا مدة، والسكرتير ما
      // يعرف مدة الموعد إلا لو صاحب العمل قالها.
      end: tz.TZDateTime.from(
        appointment.at.add(const Duration(hours: 1)),
        location,
      ),
    );

    final result = await _plugin.createOrUpdateEvent(event);
    if (result?.isSuccess ?? false) return result?.data;

    debugPrint('ما قدرت أضيف الحدث للتقويم: ${result?.errors}');
    return null;
  }

  Future<void> deleteEvent(String eventId) async {
    final calendar = await _writableCalendar();
    if (calendar?.id == null) return;
    await _plugin.deleteEvent(calendar!.id, eventId);
  }
}
