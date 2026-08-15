import 'package:sqflite/sqflite.dart';

import '../models/appointment.dart';
import '../models/server_action.dart';

/// قراءة وكتابة المواعيد المحلية.
class AppointmentStore {
  AppointmentStore(this._db);

  final Database _db;

  /// عدّاد بيضمن تفرّد الـid حتى لو اتعمل أكتر من ميعاد في نفس الملي ثانية
  /// (بيحصل لما الموديل يرجّع كذا create في رسالة واحدة).
  int _sequence = 0;

  String _newId() {
    _sequence = (_sequence + 1) % 1000;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return '$stamp-$_sequence';
  }

  Future<List<Appointment>> all() async {
    final rows = await _db.query('appointments', orderBy: 'at_utc ASC');
    return rows.map(Appointment.fromRow).toList(growable: false);
  }

  /// المواعيد اللي لسه جاية ومش خالصة — دي اللي بتتجدول وبتتبعت للسيرفر.
  Future<List<Appointment>> upcoming() async {
    final rows = await _db.query(
      'appointments',
      where: 'done = 0 AND at_utc >= ?',
      whereArgs: [DateTime.now().toUtc().toIso8601String()],
      orderBy: 'at_utc ASC',
    );
    return rows.map(Appointment.fromRow).toList(growable: false);
  }

  Future<Appointment?> byId(String id) async {
    final rows = await _db.query(
      'appointments',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Appointment.fromRow(rows.first);
  }

  Future<Appointment> insert(Appointment appointment) async {
    await _db.insert(
      'appointments',
      appointment.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return appointment;
  }

  Future<void> update(Appointment appointment) async {
    await _db.update(
      'appointments',
      appointment.toRow(),
      where: 'id = ?',
      whereArgs: [appointment.id],
    );
  }

  Future<void> delete(String id) async {
    await _db.delete('appointments', where: 'id = ?', whereArgs: [id]);
  }

  /// ينفّذ أوامر السيرفر ويرجّع اللي اتغيّر فعلًا.
  ///
  /// أمر بيشاور على ميعاد مش موجود بيتتجاهل بدل ما يوقّع العملية كلها — ممكن
  /// المستخدم يكون مسحه من التطبيق قبل ما الرد يوصل.
  Future<List<Appointment>> applyActions(List<ServerAction> actions) async {
    final touched = <Appointment>[];

    for (final action in actions) {
      switch (action.type) {
        case ActionType.create:
          final created = Appointment(
            id: _newId(),
            title: action.title!,
            at: action.at!,
            remindBeforeMinutes: action.remindBeforeMinutes ?? 60,
            repeat: action.repeat ?? Repeat.none,
            notes: action.notes ?? '',
          );
          await insert(created);
          touched.add(created);

        case ActionType.update:
          final existing = await byId(action.id!);
          if (existing == null) continue;
          final updated = existing.copyWith(
            title: action.title,
            at: action.at,
            remindBeforeMinutes: action.remindBeforeMinutes,
            repeat: action.repeat,
            notes: action.notes,
          );
          await update(updated);
          touched.add(updated);

        case ActionType.complete:
          final existing = await byId(action.id!);
          if (existing == null) continue;
          final finished = existing.copyWith(done: true);
          await update(finished);
          touched.add(finished);

        case ActionType.delete:
          final existing = await byId(action.id!);
          if (existing == null) continue;
          await delete(action.id!);
          touched.add(existing);

        case ActionType.unknown:
          continue;
      }
    }

    return touched;
  }
}
