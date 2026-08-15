import 'package:flutter/foundation.dart';

/// تكرار الميعاد. القيم مطابقة لـ REPEAT_VALUES في backend/secretary/tools.py.
enum Repeat {
  none,
  daily,
  weekly,
  monthly,
  yearly;

  static Repeat parse(String? value) => Repeat.values.firstWhere(
    (r) => r.name == value,
    orElse: () => Repeat.none,
  );

  String get arabicLabel => switch (this) {
    Repeat.none => 'مرة وحدة',
    Repeat.daily => 'كل يوم',
    Repeat.weekly => 'كل أسبوع',
    Repeat.monthly => 'كل شهر',
    Repeat.yearly => 'كل سنة',
  };
}

/// مصدر الموعد. يحدد إذا كان السكرتير يقدر يعدّله ولا لا.
enum AppointmentSource {
  /// موعد سجّله السكرتير — قابل للتعديل والإلغاء.
  sekerter,

  /// حدث من تقويم الجهاز — للقراءة بس.
  calendar;

  static AppointmentSource parse(String? value) =>
      AppointmentSource.values.firstWhere(
        (s) => s.name == value,
        orElse: () => AppointmentSource.sekerter,
      );
}

/// ميعاد واحد زي ما هو متخزّن على الجهاز.
///
/// [at] متخزّن UTC في قاعدة البيانات وبيتحوّل للتوقيت المحلي عند القراءة، عشان
/// المواعيد ما تزحفش لو المستخدم سافر أو التوقيت الصيفي اتغيّر.
@immutable
class Appointment {
  const Appointment({
    required this.id,
    required this.title,
    required this.at,
    this.remindBeforeMinutes = 60,
    this.repeat = Repeat.none,
    this.notes = '',
    this.done = false,
    this.source = AppointmentSource.sekerter,
    this.calendarEventId,
  });

  final String id;
  final String title;
  final DateTime at;
  final int remindBeforeMinutes;
  final Repeat repeat;
  final String notes;
  final bool done;
  final AppointmentSource source;

  /// معرّف الحدث المقابل في تقويم الجهاز، لو انضاف له.
  final String? calendarEventId;

  /// أحداث التقويم للقراءة بس — السكرتير ما يعدّلها ولا يلغيها.
  bool get isEditable => source == AppointmentSource.sekerter;

  /// وقت رنّة التذكير. ممكن يكون في الماضي لو الميعاد قريب أوي — المسؤول عن
  /// فلترة دي هو المجدول مش الموديل.
  DateTime get remindAt => at.subtract(Duration(minutes: remindBeforeMinutes));

  bool get isPast => at.isBefore(DateTime.now());

  Appointment copyWith({
    String? title,
    DateTime? at,
    int? remindBeforeMinutes,
    Repeat? repeat,
    String? notes,
    bool? done,
    String? calendarEventId,
  }) => Appointment(
    id: id,
    title: title ?? this.title,
    at: at ?? this.at,
    remindBeforeMinutes: remindBeforeMinutes ?? this.remindBeforeMinutes,
    repeat: repeat ?? this.repeat,
    notes: notes ?? this.notes,
    done: done ?? this.done,
    source: source,
    calendarEventId: calendarEventId ?? this.calendarEventId,
  );

  /// صف قاعدة البيانات المحلية.
  Map<String, Object?> toRow() => {
    'id': id,
    'title': title,
    'at_utc': at.toUtc().toIso8601String(),
    'remind_before_minutes': remindBeforeMinutes,
    'repeat': repeat.name,
    'notes': notes,
    'done': done ? 1 : 0,
    'source': source.name,
    'calendar_event_id': calendarEventId,
  };

  factory Appointment.fromRow(Map<String, Object?> row) => Appointment(
    id: row['id']! as String,
    title: row['title']! as String,
    at: DateTime.parse(row['at_utc']! as String).toLocal(),
    remindBeforeMinutes: row['remind_before_minutes']! as int,
    repeat: Repeat.parse(row['repeat'] as String?),
    notes: (row['notes'] as String?) ?? '',
    done: (row['done'] as int? ?? 0) == 1,
    source: AppointmentSource.parse(row['source'] as String?),
    calendarEventId: row['calendar_event_id'] as String?,
  );

  /// الشكل اللي بيتبعت للسيرفر كسياق. الوقت بيتبعت بالتوقيت المحلي بفرقه عشان
  /// الموديل يشوف نفس الساعة اللي المستخدم شايفها.
  Map<String, Object?> toApi() => {
    'id': id,
    'title': title,
    'at': at.toIso8601String(),
    'remind_before_minutes': remindBeforeMinutes,
    'repeat': repeat.name,
    'notes': notes,
    'done': done,
    'source': source.name,
  };

  @override
  bool operator ==(Object other) =>
      other is Appointment &&
      other.id == id &&
      other.title == title &&
      other.at == at &&
      other.remindBeforeMinutes == remindBeforeMinutes &&
      other.repeat == repeat &&
      other.notes == notes &&
      other.done == done &&
      other.source == source;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    at,
    remindBeforeMinutes,
    repeat,
    notes,
    done,
    source,
  );
}
