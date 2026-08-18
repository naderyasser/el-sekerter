/// يرسم شاشات التطبيق الحقيقية ويصوّرها PNG — من غير محاكي ولا SDK.
///
/// مش اختبار نجاح/فشل: أداة عرض. بتشغّل شجرة الودجت الفعلية (SekerterApp
/// وأولاده) بحجم موبايل، بتحط فيها بيانات، وبتصوّر كل شاشة لملف PNG تحت
/// build/screens/. الخط والثيم واللوجو والعربي كلهم زي الجهاز بالظبط —
/// اللي مش موجود بس هو نظام أندرويد تحت (الجدولة والإشعارات مبدّلة).
///
///   flutter test test/screenshots_test.dart --update-goldens
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:sekerter/api/api_client.dart';
import 'package:sekerter/app.dart';
import 'package:sekerter/data/appointment_store.dart';
import 'package:sekerter/data/chat_store.dart';
import 'package:sekerter/data/database.dart';
import 'package:sekerter/data/settings_store.dart';
import 'package:sekerter/models/appointment.dart';
import 'package:sekerter/models/chat_message.dart';
import 'package:sekerter/notifications/reminder_scheduler.dart';
import 'package:sekerter/state/providers.dart';

class RecordingPlugin implements FlutterLocalNotificationsPlugin {
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #resolvePlatformSpecificImplementation) return null;
    return Future<void>.value();
  }
}

class MemoryStorage implements FlutterSecureStorage {
  final _v = <String, String>{};
  @override
  dynamic noSuchMethod(Invocation i) {
    final k = i.namedArguments[#key] as String?;
    switch (i.memberName) {
      case #read:
        return Future<String?>.value(_v[k]);
      case #write:
        _v[k!] = i.namedArguments[#value] as String;
        return Future<void>.value();
      default:
        return Future<void>.value();
    }
  }
}

class CannedServer implements HttpClientAdapter {
  CannedServer(this.reply);
  Map<String, Object?> Function(RequestOptions) reply;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async =>
      ResponseBody.fromString(jsonEncode(reply(o)), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
  @override
  void close({bool force = false}) {}
}

Future<void> _loadFonts() async {
  final manifest = json.decode(
    await rootBundle.loadString('FontManifest.json'),
  ) as List<dynamic>;
  for (final family in manifest) {
    final loader = FontLoader(family['family'] as String);
    for (final f in family['fonts'] as List<dynamic>) {
      loader.addFont(rootBundle.load(f['asset'] as String));
    }
    await loader.load();
  }
}

/// ضخ محدود: المؤشر الدائري بيلف للأبد فـpumpAndSettle بيعلّق. بنضخ
/// عدد إطارات ثابت — كفاية إن البيانات تحمّل والشاشة تستقر.
Future<void> _pump(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await _pump(tester);
  // matchesGoldenFile بيرندر شجرة الودجت لـPNG فعلي ويكتبه مع
  // --update-goldens — ده أضمن طريق التقاط في flutter test بلا SDK.
  await expectLater(
    find.byType(SekerterApp),
    matchesGoldenFile('build/screens/$name.png'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Riyadh'));

  late AppDatabase db;
  late SettingsStore settings;
  final server = CannedServer((_) => {'reply': 'تم.', 'actions': const []});

  setUp(() async {
    db = await AppDatabase.open(
      fileName: 'shots_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    settings = SettingsStore(MemoryStorage());
  });

  Widget wrap() {
    final dio = Dio()..httpClientAdapter = server;
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        schedulerProvider.overrideWithValue(ReminderScheduler(RecordingPlugin())),
        settingsStoreProvider.overrideWithValue(settings),
        apiClientProvider.overrideWithValue(ApiClient(settings, dio: dio)),
      ],
      child: const SekerterApp(),
    );
  }

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _loadFonts();
  }

  testWidgets('شاشة الإعداد الأول', (tester) async {
    await phone(tester);
    await tester.pumpWidget(wrap());
    await _pump(tester);
    await _shoot(tester, '1-setup');
  });

  testWidgets('الشات بمحادثة حقيقية', (tester) async {
    await phone(tester);
    await settings.setApiBaseUrl('https://el-sekerter.meena-alaqariya.com');
    await settings.setApiToken('token');

    // محادثة محفوظة زي ما بتظهر فعليًا بعد الاستخدام.
    final chat = ChatStore(db.db);
    DateTime t(int m) => DateTime.now().subtract(Duration(minutes: m));
    await chat.add(ChatMessage(id: 0, sender: Sender.user, text: 'صباح الخير، عندي اجتماع مع أبو سعد بكرة الساعة خمسة العصر', at: t(9)));
    await chat.add(ChatMessage(id: 0, sender: Sender.secretary, text: 'أبشر، سجّلت اجتماع أبو سعد بكرة الساعة ٥ العصر وأذكّرك قبله بساعة.', at: t(9)));
    await chat.add(ChatMessage(id: 0, sender: Sender.user, text: 'وذكّرني بدواء الضغط كل يوم الساعة ٩ الصبح', at: t(6)));
    await chat.add(ChatMessage(id: 0, sender: Sender.secretary, text: 'تمام، دواء الضغط كل يوم ٩ الصبح — بذكّرك في وقته.', at: t(6)));
    await chat.add(ChatMessage(id: 0, sender: Sender.user, text: 'ابعت لسعد على الواتس قل له تأخرت شوي', at: t(3)));
    await chat.add(ChatMessage(id: 0, sender: Sender.secretary, text: 'فتحت واتساب لسعد والرسالة جاهزة — اضغط إرسال.', at: t(3)));

    await tester.pumpWidget(wrap());
    await _pump(tester);
    await _shoot(tester, '2-chat');
  });

  testWidgets('شاشة مواعيدي', (tester) async {
    await phone(tester);
    await settings.setApiBaseUrl('https://el-sekerter.meena-alaqariya.com');
    await settings.setApiToken('token');

    final store = AppointmentStore(db.db);
    final now = DateTime.now();
    await store.insert(Appointment(id: 'a', title: 'اجتماع أبو سعد', at: now.add(const Duration(days: 1, hours: 3))));
    await store.insert(Appointment(id: 'b', title: 'موعد الدكتور', at: now.add(const Duration(days: 2, hours: 1)), remindBeforeMinutes: 1440));
    await store.insert(Appointment(id: 'c', title: 'دواء الضغط', at: now.add(const Duration(hours: 14)), repeat: Repeat.daily));
    await store.insert(Appointment(id: 'd', title: 'تسليم الشحنة', at: now.subtract(const Duration(days: 1)), done: true));

    await tester.pumpWidget(wrap());
    await _pump(tester);
    // ننتقل لتبويب مواعيدي
    await tester.tap(find.text('مواعيدي').last);
    await _pump(tester);
    await _shoot(tester, '3-appointments');
  });
}
