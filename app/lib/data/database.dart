import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// قاعدة البيانات المحلية — دي مصدر الحقيقة للمواعيد. السيرفر مبيخزّنش حاجة.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const int _version = 3;

  static Future<AppDatabase> open({String fileName = 'sekerter.db'}) async {
    final path = p.join(await getDatabasesPath(), fileName);
    final db = await openDatabase(
      path,
      version: _version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
      onUpgrade: _upgrade,
    );
    return AppDatabase._(db);
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE appointments (
        id                     TEXT    PRIMARY KEY,
        title                  TEXT    NOT NULL,
        at_utc                 TEXT    NOT NULL,
        remind_before_minutes  INTEGER NOT NULL DEFAULT 60,
        repeat                 TEXT    NOT NULL DEFAULT 'none',
        notes                  TEXT    NOT NULL DEFAULT '',
        done                   INTEGER NOT NULL DEFAULT 0,
        source                 TEXT    NOT NULL DEFAULT 'sekerter',
        calendar_event_id      TEXT,
        snooze_until           TEXT
      )
    ''');

    // شاشة المواعيد بترتّب بالوقت دايمًا، والمجدول بيدوّر على أقرب المواعيد.
    await db.execute(
      'CREATE INDEX idx_appointments_at ON appointments (at_utc)',
    );

    await db.execute('''
      CREATE TABLE chat_messages (
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        sender  TEXT    NOT NULL,
        text    TEXT    NOT NULL,
        at_utc  TEXT    NOT NULL,
        failed  INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// ترقيات الشكل. لازم تكون تراكمية — مستخدم على نسخة قديمة يمر بكل خطوة.
  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) {
      await db.execute(
        "ALTER TABLE appointments ADD COLUMN source TEXT NOT NULL "
        "DEFAULT 'sekerter'",
      );
      await db.execute(
        'ALTER TABLE appointments ADD COLUMN calendar_event_id TEXT',
      );
    }
    if (from < 3) {
      // «أجّل ربع ساعة» من زرار الإشعار.
      await db.execute('ALTER TABLE appointments ADD COLUMN snooze_until TEXT');
    }
  }

  Future<void> close() => db.close();
}
