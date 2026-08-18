/// اختبارات على أندرويد حقيقي (محاكي) — مش بدائل مسجّلة.
///
/// كل اختبارات `test/` بتستبدل نظام التشغيل بمسجّلات، وده كان كافي لكل
/// حاجة ما عدا السؤال الجوهري: هل النظام نفسه بيقبل الجدولة وبيطلّع
/// الإشعار؟ هنا الإجابة بتيجي من أندرويد فعلًا:
///
///   • القناة v2 (صوت المنبّه) اتسجّلت عند النظام والقديمة اتمسحت.
///   • rescheduleAll بتحجز تذكيرات حقيقية عند AlarmManager.
///   • المتكرر اللي مرّته الأولى فاتت بيتجدول للمرة الجاية (العلة اللي
///     كانت بتموّت «كل أحد الساعة ٩» بعد أول رنّة).
///   • الإشعار **بينزل فعلًا** في وقته — مش بس بيتجدول.
///   • قاعدة البيانات الحقيقية (sqflite على أندرويد) بتحفظ وبترجّع.
///
/// بتتشغل من .github/workflows/deep-test.yml على محاكي أندرويد ١٢
/// (API 32) — مختار عن قصد: قبل إذن POST_NOTIFICATIONS بتاع ١٣+، فمافيش
/// حوار نظام محتاج ضغطة بشرية، والإشعارات مسموحة افتراضيًا.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:sekerter/core/config.dart';
import 'package:sekerter/data/appointment_store.dart';
import 'package:sekerter/data/database.dart';
import 'package:sekerter/models/appointment.dart';
import 'package:sekerter/notifications/reminder_scheduler.dart';

/// في وضع «الجدولة الدقيقة ممنوعة» (بيتظبط من الـworkflow بالـadb) بنتأكد
/// من السقوط الآمن بس — الرنّة غير الدقيقة ممكن تتأخر دقايق فمش بننتظرها.
const bool expectExact = bool.fromEnvironment(
  'EXPECT_EXACT',
  defaultValue: true,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final scheduler = ReminderScheduler();
  // نسخة تانية من الإضافة للفحص — الحالة عند النظام مش عند الكائن،
  // فلو التذكير باين من هنا يبقى محجوز عند أندرويد بجد.
  final probe = FlutterLocalNotificationsPlugin();

  Appointment appt(
    String id,
    String title, {
    Duration fromNow = const Duration(hours: 3),
    Repeat repeat = Repeat.none,
    int remindBefore = 60,
  }) => Appointment(
    id: id,
    title: title,
    at: DateTime.now().add(fromNow),
    remindBeforeMinutes: remindBefore,
    repeat: repeat,
  );

  Future<List<PendingNotificationRequest>> pendingReminders() async {
    final all = await probe.pendingNotificationRequests();
    return all.where((r) => r.id < 1900000000).toList();
  }

  setUpAll(() async {
    await scheduler.initialize();
  });

  testWidgets('أيقونة شريط الحالة موجودة في الـAPK — مش متشالة بالتصغير', (
    tester,
  ) async {
    // التصغير (resource shrinking) شال ic_stat_sekerter من نسخة release
    // لأنها بتتنده من Dart بالاسم كنص ومفيش مرجع ليها في الكود الأصلي.
    // النتيجة: تهيئة الإشعارات ترمي invalid_icon في main() قبل runApp،
    // والتطبيق يعلّق على شاشة الفتح للأبد. keep.xml بيمنع ده — والاختبار
    // ده بيقفل الباب: initialize بتنجح يعني المورد موجود ومقروء.
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_sekerter'),
      ),
    );
    // لو المورد ناقص، السطر اللي فوق بيرمي PlatformException قبل ما نوصل هنا.
    expect(true, isTrue);
  });

  testWidgets('قناة v2 بصوت المنبّه متسجّلة عند النظام والقديمة اتمسحت', (
    tester,
  ) async {
    final android = probe
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final channels = await android!.getNotificationChannels() ?? [];
    final ids = channels.map((c) => c.id).toList();

    expect(ids, contains(AppConfig.reminderChannelId));
    expect(ids, isNot(contains(AppConfig.legacyReminderChannelId)));

    final channel = channels.firstWhere(
      (c) => c.id == AppConfig.reminderChannelId,
    );
    expect(channel.importance, Importance.max);
  });

  testWidgets('rescheduleAll بتحجز تذكير حقيقي عند أندرويد', (tester) async {
    await scheduler.rescheduleAll([appt('real-1', 'اجتماع أبو سعد')]);

    final pending = await pendingReminders();
    expect(pending, hasLength(1));
    expect(pending.single.title, 'اجتماع أبو سعد');
  });

  testWidgets('المتكرر اللي فاتت مرّته الأولى لسه محجوز — مش ميّت', (
    tester,
  ) async {
    // «كل أحد الساعة ٩» اللي عدّى عليه ٣ أيام: قبل التصليح كان بيتفلتر
    // هنا ويموت في صمت. دلوقتي بيتدحرج للأسبوع الجاي.
    await scheduler.rescheduleAll([
      appt(
        'weekly-1',
        'اجتماع كل أحد',
        fromNow: const Duration(days: -3),
        repeat: Repeat.weekly,
      ),
    ]);

    final pending = await pendingReminders();
    expect(pending, hasLength(1));
    expect(pending.single.title, 'اجتماع كل أحد');
  });

  testWidgets('غير المتكرر اللي فات وقته ما بيتجدولش', (tester) async {
    await scheduler.rescheduleAll([
      appt('past-1', 'موعد فات', fromNow: const Duration(days: -1)),
    ]);
    expect(await pendingReminders(), isEmpty);
  });

  testWidgets('الإشعار بينزل فعلًا في وقته — مش بس بيتجدول', (tester) async {
    if (!expectExact) {
      // من غير جدولة دقيقة أندرويد بيأجّل الرنّة زي ما يحب — الانتظار
      // هنا يخلّي الاختبار متقلب. السقوط الآمن نفسه متغطي تحت.
      return;
    }

    // موعد بعد ساعة، والتذكير قبله بـ٦٠ دقيقة إلا ١٥ ثانية → الرنّة
    // المفروض تنزل خلال ~١٥ ثانية من دلوقتي.
    final ringing = Appointment(
      id: 'ring-1',
      title: 'رنّة التجربة الحقيقية',
      at: DateTime.now().add(const Duration(minutes: 60, seconds: 15)),
      remindBeforeMinutes: 60,
    );
    await scheduler.rescheduleAll([ringing]);
    expect(await pendingReminders(), hasLength(1));

    // استنّى النظام يطلّع الإشعار — بنسأل أندرويد نفسه عن الإشعارات
    // المعروضة حاليًا، مش أي حالة داخلية عندنا.
    ActiveNotification? shown;
    for (var i = 0; i < 45 && shown == null; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final active = await probe.getActiveNotifications();
      for (final n in active) {
        if (n.title == 'رنّة التجربة الحقيقية') shown = n;
      }
    }

    expect(
      shown,
      isNotNull,
      reason: 'الإشعار اتجدول عند النظام بس ما نزلش خلال ٤٥ ثانية',
    );
    expect(shown!.channelId, AppConfig.reminderChannelId);
  });

  testWidgets('مع منع الجدولة الدقيقة: مافيش انهيار والتذكير محجوز برضه', (
    tester,
  ) async {
    // في وضع EXPECT_EXACT=false الـworkflow بيكون مانع الإذن بالـadb.
    // قبل التصليح: أول zonedSchedule يرمي استثناء بعد cancelAll — كل
    // التذكيرات تتمسح ولا واحد يتحجز. دلوقتي: سقوط لغير الدقيقة.
    await scheduler.rescheduleAll([
      appt('fallback-1', 'تذكير مع المنع'),
      appt('fallback-2', 'وتاني معاه', fromNow: const Duration(hours: 5)),
    ]);

    final pending = await pendingReminders();
    expect(pending, hasLength(2));
  });

  testWidgets('cancel بتشيل الحجز من النظام', (tester) async {
    final one = appt('cancel-1', 'هيتلغي');
    await scheduler.rescheduleAll([one]);
    expect(await pendingReminders(), hasLength(1));

    await scheduler.cancel(one.id);
    expect(await pendingReminders(), isEmpty);
  });

  testWidgets('قاعدة البيانات الحقيقية على أندرويد بتحفظ وبترجّع', (
    tester,
  ) async {
    final db = await AppDatabase.open(fileName: 'on_device_test.db');
    final store = AppointmentStore(db.db);

    final saved = await store.insert(
      appt('db-1', 'موعد في قاعدة الجهاز', remindBefore: 1440),
    );
    final loaded = await store.byId(saved.id);

    expect(loaded, isNotNull);
    expect(loaded!.title, 'موعد في قاعدة الجهاز');
    expect(loaded.remindBeforeMinutes, 1440);
    // الوقت اترجع بنفس اللحظة بعد رحلة UTC (بدقة الثانية — التخزين ISO).
    expect(
      loaded.at.difference(saved.at).inSeconds.abs(),
      lessThanOrEqualTo(1),
    );

    await db.close();
  });
}
