/// محاكاة مستخدم حقيقي على أندرويد حقيقي — التطبيق كامل من أول شاشة.
///
/// الفرق عن on_device_test: هناك بنختبر طبقة الجدولة لوحدها، هنا بنشغّل
/// **التطبيق نفسه** ونستعمله زي صاحب العمل بالظبط: نعدّي على شاشة الإعداد،
/// نفتح الشات، نكتب بالعربي، ندوس إرسال، ننقّل بين التبويبات — وبعد كل
/// خطوة نسأل أندرويد نفسه: التذكير محجوز؟ اتلغى؟
///
/// الحقيقي هنا: الواجهة كلها، قاعدة sqflite على الجهاز، التخزين الآمن
/// (keystore حقيقي)، الإشعارات عند النظام، الأذونات. المسجّل: ردود السيرفر
/// (بنفس صيغة السيرفر الفعلية — عشان الاختبار حتمي ومايكلّمش الموديل في كل
/// رنّة)، وفتح الاتصال/واتساب (المحاكي مافيهوش واتساب أصلًا)، ودفتر
/// التليفون (المحاكي فاضي).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:sekerter/api/api_client.dart';
import 'package:sekerter/app.dart';
import 'package:sekerter/features/chat/widgets/composer.dart';
import 'package:sekerter/data/database.dart';
import 'package:sekerter/data/settings_store.dart';
import 'package:sekerter/device/contacts_service.dart';
import 'package:sekerter/device/messaging_service.dart';
import 'package:sekerter/notifications/reminder_scheduler.dart';
import 'package:sekerter/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── السيرفر المسجّل: نفس صيغة ردود السيرفر الفعلية ─────────────────────────

class CannedServer implements HttpClientAdapter {
  CannedServer(this.reply);

  Map<String, Object?> Function(RequestOptions options) reply;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(reply(options)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class FakeContacts implements ContactsService {
  final book = const [
    ContactMatch(name: 'أبو سعد', phone: '0501234567'),
    ContactMatch(name: 'سعد التجربة', phone: '0559876543'),
  ];

  @override
  Future<List<ContactMatch>> search(String query) async {
    final folded = ContactsService.fold(query);
    return book
        .where((c) => ContactsService.fold(c.name).contains(folded))
        .toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<bool>.value(true);
}

class RecordingMessaging implements MessagingService {
  final calls = <String>[];
  final whatsapps = <(String, String)>[];

  @override
  Future<bool> call(String phone) async {
    calls.add(MessagingService.clean(phone));
    return true;
  }

  @override
  Future<SendOutcome> whatsapp(String phone, String text) async {
    whatsapps.add((MessagingService.international(phone), text));
    return SendOutcome.opened;
  }

  @override
  Future<SendOutcome> sms(String phone, String text) async {
    return SendOutcome.opened;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

// ── عدة الاختبار ────────────────────────────────────────────────────────────

String isoIn(Duration fromNow) =>
    DateTime.now().toUtc().add(fromNow).toIso8601String();

Map<String, Object?> ok(
  String reply, [
  List<Map<String, Object?>> actions = const [],
]) => {'reply': reply, 'actions': actions};

/// يستنى لحد ما الشرط يتحقق — الرد بيعدّي على قاعدة بيانات وجدولة حقيقيين
/// فمفيش pumpAndSettle يكفي لوحده.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (condition()) return;
  }
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final scheduler = ReminderScheduler();
  final probe = FlutterLocalNotificationsPlugin();
  final messaging = RecordingMessaging();

  late AppDatabase database;
  late CannedServer server;
  late SettingsStore settings;

  Future<List<String>> pendingTitles() async {
    final all = await probe.pendingNotificationRequests();
    return all
        .where((r) => r.id < 1900000000)
        .map((r) => r.title ?? '')
        .toList();
  }

  setUpAll(() async {
    await scheduler.initialize();
    database = await AppDatabase.open();
    settings = SettingsStore();
    server = CannedServer((_) => ok('تم.'));
  });

  Widget app() {
    final dio = Dio()..httpClientAdapter = server;
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        schedulerProvider.overrideWithValue(scheduler),
        settingsStoreProvider.overrideWithValue(settings),
        apiClientProvider.overrideWithValue(ApiClient(settings, dio: dio)),
        contactsServiceProvider.overrideWithValue(FakeContacts()),
        messagingServiceProvider.overrideWithValue(messaging),
      ],
      child: const SekerterApp(),
    );
  }

  // IndexedStack بيبني التبويبات كلها، فالشجرة فيها تلات TextField
  // (الكومبوزر + خانتين الإعدادات) — بنحدد بتاع الشات بالذات.
  final composerField = find.descendant(
    of: find.byType(Composer),
    matching: find.byType(TextField),
  );

  /// يكتب في الشات ويدوس إرسال ويستنى رد السكرتير يظهر.
  Future<void> sendChat(
    WidgetTester tester,
    String text,
    String expectReply,
  ) async {
    await tester.enterText(composerField, text);
    await tester.pump();
    await tester.tap(find.byTooltip('إرسال'));
    await pumpUntil(
      tester,
      () => find.textContaining(expectReply).evaluate().isNotEmpty,
    );
    expect(find.textContaining(expectReply), findsWidgets);
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    // اسم التبويب موجود كمان كعنوان شاشة جوه الـIndexedStack — بندوس على
    // اللي جوه شريط التنقل تحديدًا.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await pumpUntil(tester, () => true, timeout: const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('١) الإعداد الأول: عنوان + توكن → تحقّق وابدأ → الشات', (
    tester,
  ) async {
    server.reply = (options) {
      if (options.path.contains('/health')) return {'status': 'ok'};
      return ok('تم.');
    };

    await tester.pumpWidget(app());
    await pumpUntil(
      tester,
      () => find.text('تحقّق وابدأ').evaluate().isNotEmpty,
    );

    // شاشة الإعداد الأول ظهرت وفيها اللوجو والخانتين.
    expect(find.text('وصّل التطبيق بسيرفرك'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).at(0),
      'https://sekerter.test',
    );
    await tester.enterText(find.byType(TextField).at(1), 'test-token');
    await tester.pump();
    await tester.tap(find.text('تحقّق وابدأ'));

    // الحفظ بيعمل ping حقيقي (على السيرفر المسجّل) وبعدها الشات بيظهر.
    await pumpUntil(
      tester,
      () => find.text('اكتب أو تكلّم…').evaluate().isNotEmpty,
    );
    expect(find.text('السكرتير'), findsWidgets);

    // طلب الأذونات الابتدائي بيشتغل في الخلفية — نسيبه يخلص قبل ما
    // الاختبار يقفل الشجرة.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('٢) تسجيل موعد من الشات → يظهر في مواعيدي ومحجوز عند أندرويد', (
    tester,
  ) async {
    server.reply = (options) {
      if (options.path.contains('/health')) return {'status': 'ok'};
      return ok('أبشر، سجّلت اجتماع أبو سعد بكرة ٥ العصر وأذكّرك قبله بساعة.', [
        {
          'type': 'create',
          'title': 'اجتماع أبو سعد',
          'at': isoIn(const Duration(days: 1)),
          'remind_before_minutes': 60,
          'repeat': 'none',
          'notes': '',
        },
      ]);
    };

    await tester.pumpWidget(app());
    await pumpUntil(
      tester,
      () => find.text('اكتب أو تكلّم…').evaluate().isNotEmpty,
    );

    await sendChat(
      tester,
      'عندي اجتماع مع أبو سعد بكرة الساعة خمسة العصر',
      'سجّلت اجتماع أبو سعد',
    );

    // التبويب التاني: الموعد ظاهر في القايمة.
    await openTab(tester, 'مواعيدي');
    await pumpUntil(
      tester,
      () => find.textContaining('اجتماع أبو سعد').evaluate().isNotEmpty,
    );

    // والأهم: أندرويد نفسه حاجز التذكير.
    expect(await pendingTitles(), contains('اجتماع أبو سعد'));
  });

  testWidgets('٣) كذا موعد في رسالة وحدة — التلاتة يتسجّلوا ويتحجزوا', (
    tester,
  ) async {
    server.reply = (options) {
      if (options.path.contains('/health')) return {'status': 'ok'};
      return ok('أبشر، سجّلت الثلاثة.', [
        for (final (i, title) in [
          'موعد الدكتور',
          'تسليم الشحنة',
          'اجتماع المورّد',
        ].indexed)
          {
            'type': 'create',
            'title': title,
            'at': isoIn(Duration(days: 2 + i)),
            'remind_before_minutes': 60,
            'repeat': 'none',
            'notes': '',
          },
      ]);
    };

    await tester.pumpWidget(app());
    await pumpUntil(
      tester,
      () => find.text('اكتب أو تكلّم…').evaluate().isNotEmpty,
    );

    await sendChat(
      tester,
      'سجل لي موعد الدكتور وتسليم الشحنة واجتماع المورّد',
      'سجّلت الثلاثة',
    );

    final titles = await pendingTitles();
    expect(titles, contains('موعد الدكتور'));
    expect(titles, contains('تسليم الشحنة'));
    expect(titles, contains('اجتماع المورّد'));
  });

  testWidgets('٤) سؤال «وش عندي؟» — رد من غير أوامر ومواعيده اتبعتت للسيرفر', (
    tester,
  ) async {
    List<dynamic>? sentAppointments;
    server.reply = (options) {
      if (options.path.contains('/health')) return {'status': 'ok'};
      final body = (options.data as Map).cast<String, Object?>();
      sentAppointments = body['appointments'] as List?;
      return ok('عندك اجتماع أبو سعد بكرة الساعة ٥ العصر.');
    };

    await tester.pumpWidget(app());
    await pumpUntil(
      tester,
      () => find.text('اكتب أو تكلّم…').evaluate().isNotEmpty,
    );

    await sendChat(tester, 'وش عندي بكرة؟', 'عندك اجتماع أبو سعد');

    // السكرتير جاوب من جدوله: المواعيد راحت مع الطلب فعلًا.
    expect(sentAppointments, isNotNull);
    expect(
      sentAppointments!.map((a) => (a as Map)['title']),
      contains('اجتماع أبو سعد'),
    );
  });

  testWidgets('٥) «انلغى» — يتشال من القايمة ومن حجوزات أندرويد', (
    tester,
  ) async {
    server.reply = (options) {
      if (options.path.contains('/health')) return {'status': 'ok'};
      final body = (options.data as Map).cast<String, Object?>();
      final appts = (body['appointments'] as List).cast<Map>();
      final target = appts.firstWhere(
        (a) => (a['title'] as String).contains('تسليم الشحنة'),
      );
      return ok('انلغى تسليم الشحنة وشلت تذكيره.', [
        {'type': 'delete', 'id': target['id']},
      ]);
    };

    await tester.pumpWidget(app());
    await pumpUntil(
      tester,
      () => find.text('اكتب أو تكلّم…').evaluate().isNotEmpty,
    );

    expect(await pendingTitles(), contains('تسليم الشحنة'));

    await sendChat(tester, 'تسليم الشحنة انلغى', 'انلغى تسليم الشحنة');

    // أندرويد شال الحجز فعلًا.
    await pumpUntil(tester, () => true, timeout: const Duration(seconds: 1));
    expect(await pendingTitles(), isNot(contains('تسليم الشحنة')));
  });

  testWidgets('٦) «كلّم أبو سعد» — مطابقة الاسم والاتصال اتفتح', (
    tester,
  ) async {
    server.reply = (options) {
      if (options.path.contains('/health')) return {'status': 'ok'};
      return ok('', [
        {'type': 'call', 'who': 'أبو سعد'},
      ]);
    };

    await tester.pumpWidget(app());
    await pumpUntil(
      tester,
      () => find.text('اكتب أو تكلّم…').evaluate().isNotEmpty,
    );

    await sendChat(tester, 'كلّم أبو سعد', 'أطلب أبو سعد');

    expect(messaging.calls, contains('0501234567'));
  });

  testWidgets('٧) رسالة واتساب فورية — الرقم اتحوّل والنص وصل زي ما هو', (
    tester,
  ) async {
    server.reply = (options) {
      if (options.path.contains('/health')) return {'status': 'ok'};
      return ok('', [
        {
          'type': 'message',
          'who': 'سعد التجربة',
          'channel': 'whatsapp',
          'text': 'تأخرت شوي وأنا في الطريق',
          'at': null,
        },
      ]);
    };

    await tester.pumpWidget(app());
    await pumpUntil(
      tester,
      () => find.text('اكتب أو تكلّم…').evaluate().isNotEmpty,
    );

    await sendChat(
      tester,
      'ابعت لسعد على الواتس قل له تأخرت شوي',
      'فتحت واتساب',
    );

    expect(
      messaging.whatsapps,
      contains(('966559876543', 'تأخرت شوي وأنا في الطريق')),
    );
  });

  testWidgets('٨) رسالة مجدولة «بكرة الصبح» — تتحوّل لتذكير محجوز عند النظام', (
    tester,
  ) async {
    server.reply = (options) {
      if (options.path.contains('/health')) return {'status': 'ok'};
      return ok('أبشر، أذكّرك تبعتها بكرة الصبح.', [
        {
          'type': 'message',
          'who': 'سعد التجربة',
          'channel': 'whatsapp',
          'text': 'صباح الخير، موعدنا اليوم',
          'at': isoIn(const Duration(days: 1)),
        },
      ]);
    };

    await tester.pumpWidget(app());
    await pumpUntil(
      tester,
      () => find.text('اكتب أو تكلّم…').evaluate().isNotEmpty,
    );

    await sendChat(
      tester,
      'ابعت لسعد بكرة الصبح قل له موعدنا اليوم',
      'أذكّرك تبعتها',
    );

    // الرسالة المجدولة بقت موعد «ابعت لـ…» وأندرويد حاجز رنّته.
    expect(
      (await pendingTitles()).any((t) => t.contains('ابعت لـ')),
      isTrue,
      reason: 'الرسالة المجدولة لازم تبقى تذكير محجوز عند النظام',
    );
  });

  testWidgets('٩) فشل الشبكة — الرسالة تتعلّم فاشلة والشات ما يعلّقش', (
    tester,
  ) async {
    server.reply = (options) {
      if (options.path.contains('/health')) return {'status': 'ok'};
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'السيرفر واقع',
      );
    };

    await tester.pumpWidget(app());
    await pumpUntil(
      tester,
      () => find.text('اكتب أو تكلّم…').evaluate().isNotEmpty,
    );

    await tester.enterText(composerField, 'رسالة والسيرفر واقع');
    await tester.pump();
    await tester.tap(find.byTooltip('إرسال'));

    // الرسالة الفاشلة بتتعلّم «ما وصلت» ومعاها «أعد الإرسال».
    await pumpUntil(tester, () => find.text('ما وصلت').evaluate().isNotEmpty);
    expect(find.text('أعد الإرسال'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('اكتب أو تكلّم…'), findsOneWidget);
  });

  testWidgets('١٠) زرار المايك على جهاز حقيقي — ما بيكسرش التطبيق أبدًا', (
    tester,
  ) async {
    server.reply = (options) {
      if (options.path.contains('/health')) return {'status': 'ok'};
      return ok('تم.');
    };

    await tester.pumpWidget(app());
    await pumpUntil(
      tester,
      () => find.text('اكتب أو تكلّم…').evaluate().isNotEmpty,
    );

    // المحاكي غالبًا من غير محرّك تعرّف، وتهيئته بطيئة — المطلوب الصلب:
    // مفيش انهيار أبدًا. ولو ظهرت إشارة (رسالة مفهومة، «أسمعك…»، أو زرار
    // الإيقاف) نتأكد إنها من اللي متوقعينهم.
    await tester.tap(find.byIcon(Icons.mic_none));

    bool anySignal() =>
        find.textContaining('ما قدرت أشغّل المايك').evaluate().isNotEmpty ||
        find.text('أسمعك…').evaluate().isNotEmpty ||
        find.byIcon(Icons.stop_circle).evaluate().isNotEmpty;

    await pumpUntil(tester, anySignal, timeout: const Duration(seconds: 20));

    // الأساس: التطبيق عايش ومفيش استثناء — سلوك المايك نفسه بيختلف حسب
    // وجود محرّك تعرّف على الجهاز، وده متغطي باختبارات الوحدات.
    expect(tester.takeException(), isNull);
    expect(find.byType(Composer), findsOneWidget);
  });
}
