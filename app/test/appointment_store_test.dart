import 'package:flutter_test/flutter_test.dart';
import 'package:sekerter/data/appointment_store.dart';
import 'package:sekerter/models/appointment.dart';
import 'package:sekerter/models/server_action.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// تنفيذ أوامر السيرفر على قاعدة البيانات المحلية.
///
/// ده الجزء اللي فيه بيانات صاحب العمل الحقيقية، وأي غلط هنا معناه موعد
/// ضايع أو تذكير برنّ في وقت غلط.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late AppointmentStore store;

  final at = DateTime(2026, 8, 16, 17, 30);

  setUp(() async {
    // قاعدة في الذاكرة — نظيفة لكل اختبار.
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
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
        calendar_event_id      TEXT
      )
    ''');
    store = AppointmentStore(db);
  });

  tearDown(() => db.close());

  ServerAction create({String title = 'موعد الدكتور', DateTime? when}) =>
      ServerAction(
        type: ActionType.create,
        title: title,
        at: when ?? at,
        remindBeforeMinutes: 60,
        repeat: Repeat.none,
        notes: '',
      );

  group('الإنشاء', () {
    test('أمر create يحفظ الموعد', () async {
      final touched = await store.applyActions([create()]);
      expect(touched, hasLength(1));

      final all = await store.all();
      expect(all.single.title, 'موعد الدكتور');
      expect(all.single.at, at);
    });

    test('كذا موعد في أمر واحد ياخد كل واحد id مختلف', () async {
      // نفس الملي ثانية — العدّاد هو اللي يمنع التصادم.
      await store.applyActions([
        create(title: 'الأول'),
        create(title: 'الثاني'),
        create(title: 'الثالث'),
      ]);

      final all = await store.all();
      expect(all, hasLength(3));
      expect(all.map((a) => a.id).toSet(), hasLength(3));
    });

    test('الترتيب بالوقت تصاعديًا', () async {
      await store.applyActions([
        create(title: 'متأخر', when: DateTime(2026, 8, 20)),
        create(title: 'مبكر', when: DateTime(2026, 8, 17)),
      ]);
      final all = await store.all();
      expect(all.map((a) => a.title), ['مبكر', 'متأخر']);
    });
  });

  group('التعديل', () {
    test('null معناها «سيبه زي ما هو»', () async {
      final created = (await store.applyActions([create()])).single;

      await store.applyActions([
        ServerAction(
          type: ActionType.update,
          id: created.id,
          at: DateTime(2026, 8, 18, 10, 0),
        ),
      ]);

      final updated = await store.byId(created.id);
      expect(updated!.at, DateTime(2026, 8, 18, 10, 0));
      // ما اتبعتش، فلازم يفضل زي ما هو.
      expect(updated.title, 'موعد الدكتور');
      expect(updated.remindBeforeMinutes, 60);
    });

    test('تعديل id مش موجود يتتجاهل بدل ما يوقّع الباقي', () async {
      final created = (await store.applyActions([create()])).single;

      final touched = await store.applyActions([
        ServerAction(
          type: ActionType.update,
          id: 'ghost',
          title: 'مالوش لازمة',
        ),
        ServerAction(type: ActionType.update, id: created.id, title: 'الجديد'),
      ]);

      expect(touched, hasLength(1));
      expect((await store.byId(created.id))!.title, 'الجديد');
    });
  });

  group('الإلغاء والإنهاء', () {
    test('delete يشيل الموعد ويرجّعه عشان زرار التراجع', () async {
      final created = (await store.applyActions([create()])).single;

      final touched = await store.applyActions([
        ServerAction(type: ActionType.delete, id: created.id),
      ]);

      expect(touched.single.title, 'موعد الدكتور');
      expect(await store.all(), isEmpty);
    });

    test('complete يعلّمه خلص ولا يمسحه', () async {
      final created = (await store.applyActions([create()])).single;

      await store.applyActions([
        ServerAction(type: ActionType.complete, id: created.id),
      ]);

      final finished = await store.byId(created.id);
      expect(finished!.done, isTrue);
      expect(await store.all(), hasLength(1));
    });
  });

  group('upcoming', () {
    test('يستبعد اللي فات واللي خلص', () async {
      final past = DateTime.now().subtract(const Duration(days: 1));
      final future = DateTime.now().add(const Duration(days: 1));

      await store.applyActions([
        create(title: 'فات', when: past),
        create(title: 'جاي', when: future),
      ]);

      final finished = (await store.all()).firstWhere((a) => a.title == 'جاي');
      await store.update(finished.copyWith(done: true));

      expect(await store.upcoming(), isEmpty);
    });

    test('يرجّع الجاي وغير المنجز', () async {
      await store.applyActions([
        create(title: 'جاي', when: DateTime.now().add(const Duration(days: 2))),
      ]);
      final upcoming = await store.upcoming();
      expect(upcoming.single.title, 'جاي');
    });
  });

  group('أوامر الجهاز', () {
    test('call و message ما يلمسوش قاعدة البيانات', () async {
      final touched = await store.applyActions([
        const ServerAction(type: ActionType.call, who: 'أبو سعد'),
        const ServerAction(
          type: ActionType.message,
          who: 'أبو سعد',
          channel: 'whatsapp',
          text: 'السلام عليكم',
        ),
      ]);

      expect(touched, isEmpty);
      expect(await store.all(), isEmpty);
    });

    test('نوع مجهول من سيرفر أحدث يتتجاهل', () async {
      final touched = await store.applyActions([
        const ServerAction(type: ActionType.unknown, id: 'x'),
      ]);
      expect(touched, isEmpty);
    });
  });

  group('حفظ الحقول', () {
    test('التكرار والملاحظات والمصدر يرجعوا صح بعد القراءة', () async {
      await store.applyActions([
        ServerAction(
          type: ActionType.create,
          title: 'اجتماع أسبوعي',
          at: at,
          remindBeforeMinutes: 15,
          repeat: Repeat.weekly,
          notes: 'في المكتب، جيب الملف',
        ),
      ]);

      final saved = (await store.all()).single;
      expect(saved.repeat, Repeat.weekly);
      expect(saved.remindBeforeMinutes, 15);
      expect(saved.notes, 'في المكتب، جيب الملف');
      expect(saved.source, AppointmentSource.sekerter);
      expect(saved.isEditable, isTrue);
    });

    test('مصدر التقويم مش قابل للتعديل', () {
      final event = Appointment(
        id: 'cal:1',
        title: 'حدث',
        at: at,
        source: AppointmentSource.calendar,
      );
      expect(event.isEditable, isFalse);
      expect(event.toApi()['source'], 'calendar');
    });
  });
}
