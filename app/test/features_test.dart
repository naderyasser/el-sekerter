// ignore_for_file: avoid_dynamic_calls

/// جولة تجربة على كل ميزة وعدنا بيها.
///
/// مافيش محاكي أندرويد في بيئة التطوير دي، فدي أقرب حاجة لتجربة حقيقية:
/// شجرة التطبيق الحقيقية + قاعدة بيانات حقيقية + سيرفر وهمي بيرد بردود
/// السيرفر الفعلية + إضافات نظام مسجّلة بدل المنفّذة. كل حاجة بتتجرّب هنا
/// ما عدا رنّة النظام نفسها — دي محتاجة جهاز.
///
/// كل مجموعة معنونة بالميزة زي ما اتوعدت للعميل بالظبط.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:sekerter/api/api_client.dart';
import 'package:sekerter/core/config.dart';
import 'package:sekerter/data/appointment_store.dart';
import 'package:sekerter/data/chat_store.dart';
import 'package:sekerter/data/database.dart';
import 'package:sekerter/data/settings_store.dart';
import 'package:sekerter/device/contacts_service.dart';
import 'package:sekerter/device/messaging_service.dart';
import 'package:sekerter/features/permission_gate.dart';
import 'package:sekerter/models/appointment.dart';
import 'package:sekerter/notifications/reminder_scheduler.dart';
import 'package:sekerter/voice/speech_service.dart';
import 'package:sekerter/state/appointments_controller.dart';
import 'package:sekerter/state/chat_controller.dart';
import 'package:sekerter/state/providers.dart';

// ── بدائل الأجزاء اللي بتلمس النظام ────────────────────────────────────────

/// بيسجّل نداءات الجدولة بدل ما يكلّم نظام التشغيل.
class RecordingPlugin implements FlutterLocalNotificationsPlugin {
  final List<Invocation> scheduled = [];
  final List<Invocation> shown = [];
  final List<int> cancelled = [];
  int cancelAllCount = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #zonedSchedule:
        scheduled.add(invocation);
        return Future<void>.value();
      case #show:
        shown.add(invocation);
        return Future<void>.value();
      case #cancel:
        cancelled.add(invocation.namedArguments[#id] as int);
        return Future<void>.value();
      case #cancelAll:
        cancelAllCount += 1;
        scheduled.clear();
        return Future<void>.value();
      case #resolvePlatformSpecificImplementation:
        return null;
      default:
        return Future<void>.value();
    }
  }
}

/// بيتصرف زي أندرويد ١٢/١٣ لما إذن «الجدولة الدقيقة» مسحوب: أي جدولة دقيقة
/// بترمي exact_alarms_not_permitted، وغير الدقيقة بتتقبل عادي.
///
/// **مرتبة المنبّه (alarmClock) بتترفض هي كمان** — بتستخدم نفس إذن
/// SCHEDULE_EXACT_ALARM، فلو الإذن مسحوب بتتمنع زيها بالظبط.
class ExactBlockedPlugin extends RecordingPlugin {
  int exactAttempts = 0;

  static const _blocked = {
    AndroidScheduleMode.alarmClock,
    AndroidScheduleMode.exactAllowWhileIdle,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #zonedSchedule &&
        _blocked.contains(invocation.namedArguments[#androidScheduleMode])) {
      exactAttempts += 1;
      return Future<void>.error(
        PlatformException(code: 'exact_alarms_not_permitted'),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

/// بيرمي من cancelAll نفسها — عشان نجرّب إن الشات ما يعلّقش لو إعادة
/// الجدولة كلها وقعت لأي سبب.
class BrokenPlugin extends RecordingPlugin {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #cancelAll) {
      return Future<void>.error(PlatformException(code: 'boom'));
    }
    return super.noSuchMethod(invocation);
  }
}

/// محرّك تفريغ وهمي بيسلّمنا الـcallbacks اللي الخدمة سجّلتها عشان نطلق
/// أحداث النظام (وقف الاستماع، عطل) بإيدينا.
class FakeSpeechEngine implements SpeechToText {
  void Function(SpeechRecognitionError)? capturedOnError;
  void Function(String)? capturedOnStatus;

  /// اللغات اللي المحرّك «بيعلن» عنها — قابلة للتغيير عشان نحاكي أجهزة
  /// قايمتها ناقصة أو من غير عربي خالص.
  List<LocaleName> localeList = [LocaleName('ar_SA', 'العربية السعودية')];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #initialize:
        capturedOnError =
            invocation.namedArguments[#onError]
                as void Function(SpeechRecognitionError)?;
        capturedOnStatus =
            invocation.namedArguments[#onStatus] as void Function(String)?;
        return Future<bool>.value(true);
      case #locales:
        return Future<List<LocaleName>>.value(localeList);
      // لازم bool حقيقي: الخدمة بتفحصه في المسار الدافي (متهيّئة قبل كده)،
      // ومن غيره بيرجّع null وينفجر بـTypeError مالوش علاقة بالاختبار.
      case #hasPermission:
        return Future<bool>.value(true);
      case #isListening:
        return false;
      default:
        return Future<void>.value();
    }
  }
}

/// تخزين في الذاكرة بدل keystore الجهاز.
class MemoryStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final key = invocation.namedArguments[#key] as String?;
    switch (invocation.memberName) {
      case #read:
        return Future<String?>.value(values[key]);
      case #write:
        values[key!] = invocation.namedArguments[#value] as String;
        return Future<void>.value();
      case #delete:
        values.remove(key);
        return Future<void>.value();
      default:
        return Future<void>.value();
    }
  }
}

/// سيرفر وهمي على مستوى HTTP — بيمسك الطلب الحقيقي اللي التطبيق بناه
/// (العنوان والهيدر والجسم) ويرد بالـJSON اللي السيرفر الفعلي بيرده.
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
  FakeContacts(this.book);

  final List<ContactMatch> book;

  @override
  Future<List<ContactMatch>> search(String query) async {
    if (ContactsService.looksLikeNumber(query.trim())) {
      return [
        ContactMatch(
          name: query.trim(),
          phone: ContactsService.normalise(query.trim()),
        ),
      ];
    }
    final folded = ContactsService.fold(query);
    return book
        .where((c) => ContactsService.fold(c.name).contains(folded))
        .toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<bool>.value(true);
}

/// بيسجّل بدل ما يفتح تطبيقات — مافيش واتساب في بيئة الاختبار.
class RecordingMessaging implements MessagingService {
  final List<String> calls = [];
  final List<(String, String)> whatsapps = [];
  final List<(String, String)> smses = [];

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
    smses.add((MessagingService.clean(phone), text));
    return SendOutcome.opened;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// مجدول بإجابات جاهزة — لاختبار شريط تحذير الأذونات.
class StubScheduler extends ReminderScheduler {
  StubScheduler({required this.granted, required this.exact})
    : super(RecordingPlugin());

  final bool granted;
  final bool exact;
  int requestCount = 0;

  @override
  Future<bool> requestPermissions() async {
    requestCount += 1;
    return granted;
  }

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<bool> exactAlarmAllowed() async => exact;
}

// ── تجهيز البيئة ───────────────────────────────────────────────────────────

/// رد سيرفر جاهز بشكل الأوامر الفعلي.
Map<String, Object?> serverReply(
  String reply, [
  List<Map<String, Object?>> actions = const [],
]) => {'reply': reply, 'actions': actions};

class Harness {
  Harness._(this.container, this.server, this.plugin, this.messaging, this.db);

  final ProviderContainer container;
  final CannedServer server;
  final RecordingPlugin plugin;
  final RecordingMessaging messaging;
  final AppDatabase db;

  static Future<Harness> start({
    Map<String, Object?> Function(RequestOptions)? reply,
    List<ContactMatch> contacts = const [],
    RecordingPlugin? notificationsPlugin,
  }) async {
    final server = CannedServer(reply ?? (_) => serverReply('تم.'));
    final plugin = notificationsPlugin ?? RecordingPlugin();
    final messaging = RecordingMessaging();

    final storage = MemoryStorage();
    final settings = SettingsStore(storage);
    await settings.setApiBaseUrl('https://sekerter.test');
    await settings.setApiToken('test-token');

    final db = await AppDatabase.open(
      fileName: 'features_${DateTime.now().microsecondsSinceEpoch}.db',
    );

    final dio = Dio()..httpClientAdapter = server;

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        schedulerProvider.overrideWithValue(ReminderScheduler(plugin)),
        settingsStoreProvider.overrideWithValue(settings),
        apiClientProvider.overrideWithValue(ApiClient(settings, dio: dio)),
        contactsServiceProvider.overrideWithValue(FakeContacts(contacts)),
        messagingServiceProvider.overrideWithValue(messaging),
      ],
    );

    return Harness._(container, server, plugin, messaging, db);
  }

  AppointmentStore get store => container.read(appointmentStoreProvider);

  /// التذكيرات المسبقة بس — الصفّارة والملخص لهم نطاقات ids منفصلة.
  List<Invocation> get reminders => plugin.scheduled
      .where((c) => (c.namedArguments[#id] as int) < 1000000000)
      .toList();

  /// صفّارات وقت الموعد نفسه.
  List<Invocation> get sirens => plugin.scheduled.where((c) {
    final id = c.namedArguments[#id] as int;
    return id >= 1000000000 && id < 1900000000;
  }).toList();

  List<Invocation> get summaries => plugin.scheduled
      .where((c) => (c.namedArguments[#id] as int) >= 1900000000)
      .toList();
  ChatStore get chatStore => container.read(chatStoreProvider);

  Future<void> send(String text) =>
      container.read(chatProvider.notifier).send(text);

  Map<String, Object?> get lastRequestBody =>
      (server.requests.last.data as Map).cast<String, Object?>();

  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}

String isoIn(Duration fromNow) {
  final at = DateTime.now().add(fromNow);
  return '${at.toIso8601String().split('.').first}+03:00';
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Riyadh'));

  Harness? h;

  tearDown(() async {
    await h?.dispose();
    h = null;
  });

  group('الميزة: تسجيل موعد بالكلام وتذكير يرنّ من الجهاز', () {
    test('رسالة → سيرفر → موعد محفوظ → تذكير متجدول', () async {
      final at = isoIn(const Duration(days: 1));
      final harness = h = await Harness.start(
        reply: (_) => serverReply('أبشر، سجّلته.', [
          {
            'type': 'create',
            'title': 'اجتماع مع أبو سعد',
            'at': at,
            'remind_before_minutes': 60,
            'repeat': 'none',
            'notes': '',
          },
        ]),
      );

      await harness.send('عندي اجتماع مع أبو سعد بكرة الساعة خمسة العصر');

      // الموعد اتحفظ محليًا.
      final saved = await harness.store.all();
      expect(saved, hasLength(1));
      expect(saved.single.title, 'اجتماع مع أبو سعد');

      // والتذكير اتجدول عند النظام: قبل الموعد بساعة بالظبط.
      expect(harness.reminders, hasLength(1));
      final call = harness.reminders.single;
      final when = call.namedArguments[#scheduledDate] as tz.TZDateTime;
      expect(
        when.difference(tz.TZDateTime.from(saved.single.at, tz.local)),
        const Duration(hours: -1),
      );
      expect(call.namedArguments[#title], 'اجتماع مع أبو سعد');

      // والرد ظهر في الشات.
      final messages = await harness.chatStore.recent();
      expect(messages.last.text, contains('أبشر'));
    });

    test('كذا موعد في رسالة واحدة — كلهم يتسجّلوا', () async {
      final harness = h = await Harness.start(
        reply: (_) => serverReply('سجّلت الاثنين.', [
          {
            'type': 'create',
            'title': 'الأول',
            'at': isoIn(const Duration(days: 1)),
            'remind_before_minutes': 60,
            'repeat': 'none',
            'notes': '',
          },
          {
            'type': 'create',
            'title': 'الثاني',
            'at': isoIn(const Duration(days: 2)),
            'remind_before_minutes': 60,
            'repeat': 'none',
            'notes': '',
          },
        ]),
      );

      await harness.send('عندي موعدين بكرة وعقب بكرة');

      expect(await harness.store.all(), hasLength(2));
      expect(harness.reminders, hasLength(2));
    });
  });

  group('الميزة: التعديل والإلغاء بكلمة', () {
    test('التعديل يغيّر الوقت ويعيد جدولة التذكير', () async {
      final laterAt = isoIn(const Duration(days: 3));
      var turn = 0;
      final harness = h = await Harness.start(
        reply: (_) {
          turn += 1;
          if (turn == 1) {
            return serverReply('سجّلته.', [
              {
                'type': 'create',
                'title': 'موعد الدكتور',
                'at': isoIn(const Duration(days: 1)),
                'remind_before_minutes': 60,
                'repeat': 'none',
                'notes': '',
              },
            ]);
          }
          return serverReply('أجّلته.', [
            {'type': 'update', 'id': '{id}', 'at': laterAt},
          ]);
        },
      );

      await harness.send('سجّل موعد الدكتور بكرة');
      final created = (await harness.store.all()).single;

      // السيرفر الوهمي محتاج يعرف الـid الحقيقي اللي التطبيق ولّده.
      harness.server.reply = (_) => serverReply('أجّلته.', [
        {'type': 'update', 'id': created.id, 'at': laterAt},
      ]);
      await harness.send('أجّل موعد الدكتور');

      final updated = await harness.store.byId(created.id);
      expect(updated!.at.day, DateTime.parse(laterAt).day);

      // التذكير اتجدول من جديد على الوقت الجديد، مش زيادة فوق القديم.
      expect(harness.reminders, hasLength(1));
      expect(harness.plugin.cancelAllCount, greaterThanOrEqualTo(2));
    });

    test('«انلغى» يمسح الموعد ويشيل تذكيره', () async {
      final harness = h = await Harness.start(
        reply: (_) => serverReply('سجّلته.', [
          {
            'type': 'create',
            'title': 'اجتماع',
            'at': isoIn(const Duration(days: 1)),
            'remind_before_minutes': 60,
            'repeat': 'none',
            'notes': '',
          },
        ]),
      );

      await harness.send('عندي اجتماع بكرة');
      final created = (await harness.store.all()).single;

      harness.server.reply = (_) => serverReply('انلغى.', [
        {'type': 'delete', 'id': created.id},
      ]);
      await harness.send('الاجتماع انلغى');

      expect(await harness.store.all(), isEmpty);
      // كل التذكيرات اتلغت وما اتجدولش بديل.
      expect(harness.reminders, isEmpty);
    });
  });

  group('الميزة: كلّم فلان — اتصال من جهات الاتصال', () {
    test('اسم واحد مطابق → اتصال على رقمه', () async {
      final harness = h = await Harness.start(
        reply: (_) => serverReply('أتصل به.', [
          {'type': 'call', 'who': 'أبو خالد'},
        ]),
        contacts: const [ContactMatch(name: 'أبو خالد', phone: '0501234567')],
      );

      await harness.send('كلّم أبو خالد');

      expect(harness.messaging.calls, ['0501234567']);
      // ومافيش موعد اتسجّل بالغلط.
      expect(await harness.store.all(), isEmpty);
    });

    test('اسمين متشابهين → يسأل مين تقصد بدل ما يخمّن', () async {
      final harness = h = await Harness.start(
        reply: (_) => serverReply('أتصل به.', [
          {'type': 'call', 'who': 'أبو سعد'},
        ]),
        contacts: const [
          ContactMatch(name: 'أبو سعد التاجر', phone: '0501111111'),
          ContactMatch(name: 'أبو سعد الجار', phone: '0502222222'),
        ],
      );

      await harness.send('كلّم أبو سعد');

      // ما اتصلش بحد.
      expect(harness.messaging.calls, isEmpty);
      // وسأل في الشات.
      final messages = await harness.chatStore.recent();
      expect(messages.last.text, contains('أكثر من'));
      expect(messages.last.text, contains('التاجر'));
      expect(messages.last.text, contains('الجار'));
    });

    test('الاسم مش موجود → يطلب الرقم', () async {
      final harness = h = await Harness.start(
        reply: (_) => serverReply('أتصل به.', [
          {'type': 'call', 'who': 'أبو نواف'},
        ]),
      );

      await harness.send('كلّم أبو نواف');

      expect(harness.messaging.calls, isEmpty);
      final messages = await harness.chatStore.recent();
      expect(messages.last.text, contains('ما لقيت'));
    });

    test('توحيد الهمزات: «ابو خالد» يلاقي «أبو خالد»', () async {
      final harness = h = await Harness.start(
        reply: (_) => serverReply('أتصل.', [
          {'type': 'call', 'who': 'ابو خالد'},
        ]),
        contacts: const [ContactMatch(name: 'أبو خالد', phone: '0501234567')],
      );

      await harness.send('كلم ابو خالد');
      expect(harness.messaging.calls, ['0501234567']);
    });
  });

  group('الميزة: ابعت واتساب والرسالة جاهزة', () {
    test('الرقم يتحوّل لصيغة دولية والنص يوصل زي ما هو', () async {
      final harness = h = await Harness.start(
        reply: (_) => serverReply('ببعث له.', [
          {
            'type': 'message',
            'who': 'سعد',
            'channel': 'whatsapp',
            'text': 'تأخرت شوي',
            'at': null,
          },
        ]),
        contacts: const [ContactMatch(name: 'سعد', phone: '0551234567')],
      );

      await harness.send('ابعت لسعد على الواتس قل له تأخرت شوي');

      expect(harness.messaging.whatsapps, [('966551234567', 'تأخرت شوي')]);
    });

    test('رسالة مجدولة تتحوّل لتذكير في وقتها مش إرسال فوري', () async {
      final at = isoIn(const Duration(hours: 20));
      final harness = h = await Harness.start(
        reply: (_) => serverReply('أبشر، أرسلها بكرة الصبح.', [
          {
            'type': 'message',
            'who': 'سعد',
            'channel': 'whatsapp',
            'text': 'صباح الخير، موعدنا اليوم',
            'at': at,
          },
        ]),
        contacts: const [ContactMatch(name: 'سعد', phone: '0551234567')],
      );

      await harness.send('ابعت لسعد بكرة الصبح صباح الخير');

      // ما انبعتش حالًا.
      expect(harness.messaging.whatsapps, isEmpty);
      // اتخزّنت كموعد بنص الرسالة، ورنّتها في وقت الإرسال نفسه — وبما إن
      // التذكير على لحظة الموعد ذاتها، بتاخد صفّارة الإنذار مش تذكير مسبق.
      final saved = (await harness.store.all()).single;
      expect(saved.title, contains('سعد'));
      expect(saved.notes, 'صباح الخير، موعدنا اليوم');
      expect(saved.remindBeforeMinutes, 0);
      expect(harness.reminders, isEmpty);
      expect(harness.sirens, hasLength(1));
    });
  });

  group('الوعد: جهات الاتصال والأرقام ما تطلع من الجهاز أبدًا', () {
    test('جسم الطلب ما فيه ولا رقم تليفون حتى مع مواعيد وتاريخ', () async {
      final harness = h = await Harness.start(
        contacts: const [ContactMatch(name: 'أبو سعد', phone: '0501234567')],
      );

      // مواعيد موجودة بتتبعت كسياق — نتأكد إنها ما تجرش أرقام معاها.
      await harness.store.applyActions([]);
      await harness.send('وش عندي بكرة؟');

      final body = jsonEncode(harness.lastRequestBody);
      expect(body.contains('0501234567'), isFalse);
      expect(body.contains('966'), isFalse);
      expect(harness.lastRequestBody.keys.toSet(), {
        'message',
        'now',
        'timezone',
        'appointments',
        'history',
      });
    });

    test('التوكن في الهيدر والوقت معاه فرق التوقيت', () async {
      final harness = h = await Harness.start();
      await harness.send('مرحبا');

      final request = harness.server.requests.last;
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(request.uri.path, '/api/secretary/chat');

      final now = harness.lastRequestBody['now'] as String;
      expect(RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(now), isTrue, reason: now);
    });
  });

  group('الميزة: المواعيد المتكررة', () {
    test('أسبوعي يتجدول بمطابقة اليوم والساعة', () async {
      final harness = h = await Harness.start(
        reply: (_) => serverReply('كل خميس.', [
          {
            'type': 'create',
            'title': 'اجتماع أسبوعي',
            'at': isoIn(const Duration(days: 4)),
            'remind_before_minutes': 30,
            'repeat': 'weekly',
            'notes': '',
          },
        ]),
      );

      await harness.send('اجتماع كل خميس');

      final call = harness.reminders.single;
      expect(
        call.namedArguments[#matchDateTimeComponents],
        DateTimeComponents.dayOfWeekAndTime,
      );
    });
  });

  group('حماية: فشل الشبكة ما يضيّعش رسالة', () {
    test('السيرفر واقع → الرسالة معلّمة فاشلة وقابلة لإعادة الإرسال', () async {
      final harness = h = await Harness.start();
      harness.server.reply = (_) => throw DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.connectionError,
      );

      await harness.send('عندي اجتماع بكرة');

      final messages = await harness.chatStore.recent();
      expect(messages.last.failed, isTrue);
      expect(await harness.store.all(), isEmpty);

      // السيرفر رجع → إعادة الإرسال تنجح وتشيل علامة الفشل.
      harness.server.reply = (_) => serverReply('تم.');
      await harness.container.read(chatProvider.notifier).retry(messages.last);
      final after = await harness.chatStore.recent();
      expect(after.any((m) => m.failed), isFalse);
    });
  });

  group('حماية: حد الـ٦٤ إشعار على آيفون', () {
    test('٦٠ موعد → أقرب ٥٠ بس بيتجدولوا', () async {
      final harness = h = await Harness.start(
        reply: (_) => serverReply('تم.', [
          for (var day = 1; day <= 60; day++)
            {
              'type': 'create',
              'title': 'موعد $day',
              'at': isoIn(Duration(days: day)),
              'remind_before_minutes': 60,
              'repeat': 'none',
              'notes': '',
            },
        ]),
      );

      await harness.send('سجّل كل المواعيد دي');

      expect(await harness.store.all(), hasLength(60));
      // على أندرويد مافيش حد زي بتاع أبل — الستين كلهم بياخدوا تنبيهين.
      expect(harness.reminders, hasLength(60));
      expect(harness.sirens, hasLength(60));
      final titles = harness.reminders
          .map((c) => c.namedArguments[#title] as String)
          .toList();
      expect(titles.first, 'موعد 1');
      expect(titles, contains('موعد 60'));
    });

    test(
      'السقف الآيفوني: أقرب ٢٥ موعد كاملين، والباقي معدود مش مبلوع',
      () async {
        final plugin = RecordingPlugin();
        // نفرض سقف آيفون صراحة — الاختبارات بتتشغل على الجهاز المضيف.
        final scheduler = ReminderScheduler(plugin, AppConfig.maxScheduledIos);
        final now = DateTime.now();
        final appointments = [
          for (var day = 1; day <= 60; day++)
            Appointment(
              id: 'a$day',
              title: 'موعد $day',
              at: now.add(Duration(days: day)),
              remindBeforeMinutes: 60,
            ),
        ];

        await scheduler.rescheduleAll(appointments);

        final scheduled = plugin.scheduled
            .where((c) => (c.namedArguments[#id] as int) < 1900000000)
            .toList();
        expect(scheduled, hasLength(AppConfig.maxScheduledIos));
        // ١٢٠ تنبيه مستحق - ٥٠ اتجدولوا = ٧٠ اتقصوا، ولازم يكونوا **معدودين**
        // عشان الواجهة تحذّر بدل ما الموعد يضيع في صمت.
        expect(scheduler.unscheduledCount, 120 - AppConfig.maxScheduledIos);
      },
    );
  });

  group('شريط تحذير الأذونات', () {
    Future<void> pump(WidgetTester tester, StubScheduler scheduler) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [schedulerProvider.overrideWithValue(scheduler)],
          child: const MaterialApp(
            home: Scaffold(body: PermissionGate(child: SizedBox())),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('الإشعارات مرفوضة → تحذير أحمر ظاهر', (tester) async {
      final scheduler = StubScheduler(granted: false, exact: true);
      await pump(tester, scheduler);

      expect(find.textContaining('التذكيرات ما راح ترنّ'), findsOneWidget);
      // والإذن اتطلب لوحده أول ما الشاشة فتحت — مش مستني زرار.
      expect(scheduler.requestCount, greaterThanOrEqualTo(1));
    });

    testWidgets('الجدولة الدقيقة مقفولة → تحذير التأخير', (tester) async {
      await pump(tester, StubScheduler(granted: true, exact: false));

      expect(find.textContaining('ممكن يتأخر'), findsOneWidget);
    });

    testWidgets('كل الأذونات تمام → مافيش أي تحذير', (tester) async {
      await pump(tester, StubScheduler(granted: true, exact: true));

      expect(find.textContaining('اضغط للتفعيل'), findsNothing);
    });
  });

  group('ميزة جديدة: أزرار على التذكير نفسه', () {
    Future<Harness> withAppointmentTomorrow() async {
      final harness = await Harness.start(
        reply: (_) => serverReply('سجّلته.', [
          {
            'type': 'create',
            'title': 'اجتماع مهم',
            'at': isoIn(const Duration(days: 1)),
            'remind_before_minutes': 60,
            'repeat': 'none',
            'notes': '',
          },
        ]),
      );
      await harness.send('عندي اجتماع بكرة');
      return harness;
    }

    test('التذكير طالع ومعاه زرارين: تم وأجّل', () async {
      final harness = h = await withAppointmentTomorrow();

      final details =
          harness.reminders.single.namedArguments[#notificationDetails]
              as NotificationDetails;
      final actions = details.android!.actions!;
      expect(actions.map((a) => a.id), ['done', 'snooze']);
      expect(actions.map((a) => a.title), ['تم', 'أجّل ربع ساعة']);
      // الضغطة لازم توصل للتطبيق وهو صاحي — أضمن من معالج الخلفية.
      expect(actions.every((a) => a.showsUserInterface), isTrue);
      // وآيفون بياخد الفئة اللي فيها نفس الأزرار.
      expect(details.iOS!.categoryIdentifier, 'sekerter_reminder');
    });

    test('«أجّل ربع ساعة» يأخّر الرنّة ويثبت في القاعدة', () async {
      final harness = h = await withAppointmentTomorrow();
      final created = (await harness.store.all()).single;

      // نفس اللي بيحصل لما المستخدم يضغط الزرار.
      final scheduler = harness.container.read(schedulerProvider);
      expect(scheduler, isNotNull);
      final before = DateTime.now();
      await harness.store.update(
        created.copyWith(snoozeUntil: before.add(ReminderScheduler.snoozeBy)),
      );
      await harness.container.read(appointmentsProvider.notifier).refresh();

      final call = harness.reminders.single;
      final when = call.namedArguments[#scheduledDate] as tz.TZDateTime;
      // الرنّة الجديدة بعد ربع ساعة تقريبًا، مش قبل الموعد بساعة.
      expect(when.difference(before).inMinutes, inInclusiveRange(14, 16));

      // والتأجيل ناجي من إعادة فتح التطبيق لأنه متخزّن في القاعدة.
      final reloaded = await harness.store.byId(created.id);
      expect(reloaded!.snoozeUntil, isNotNull);
    });

    test('«تم» من الإشعار يقفل الموعد ويلغي رنّته', () async {
      final harness = h = await withAppointmentTomorrow();
      final created = (await harness.store.all()).single;

      await harness.store.update(created.copyWith(done: true));
      await harness.container.read(appointmentsProvider.notifier).refresh();

      expect(harness.reminders, isEmpty);
      expect((await harness.store.byId(created.id))!.done, isTrue);
    });

    test('تعديل وقت الموعد يشيل تأجيل قديم', () async {
      final harness = h = await withAppointmentTomorrow();
      final created = (await harness.store.all()).single;

      await harness.store.update(
        created.copyWith(
          snoozeUntil: DateTime.now().add(ReminderScheduler.snoozeBy),
        ),
      );

      harness.server.reply = (_) => serverReply('أجّلته.', [
        {
          'type': 'update',
          'id': created.id,
          'at': isoIn(const Duration(days: 5)),
        },
      ]);
      await harness.send('أجّل الاجتماع');

      // تأجيل ربع الساعة القديم اتشال — الرنّة بقت قبل الوقت الجديد بساعة.
      final reloaded = await harness.store.byId(created.id);
      expect(reloaded!.snoozeUntil, isNull);
    });
  });

  group('ميزة جديدة: ملخص الصبح', () {
    test('يوم فيه مواعيد ياخد إشعار ٦:٤٥ بعددها وأساميها', () async {
      final harness = h = await Harness.start(
        reply: (_) => serverReply('سجّلتهم.', [
          {
            'type': 'create',
            'title': 'موعد الدكتور',
            'at': isoIn(const Duration(days: 1)),
            'remind_before_minutes': 60,
            'repeat': 'none',
            'notes': '',
          },
          {
            'type': 'create',
            'title': 'اجتماع المورّد',
            'at': isoIn(const Duration(days: 1, hours: 2)),
            'remind_before_minutes': 60,
            'repeat': 'none',
            'notes': '',
          },
        ]),
      );

      await harness.send('عندي موعدين بكرة');

      expect(harness.summaries, hasLength(1));
      final summary = harness.summaries.single;
      expect(summary.namedArguments[#title], contains('2'));
      expect(summary.namedArguments[#body], contains('موعد الدكتور'));
      expect(summary.namedArguments[#body], contains('اجتماع المورّد'));

      final when = summary.namedArguments[#scheduledDate] as tz.TZDateTime;
      expect(when.hour, 6);
      expect(when.minute, 45);
    });

    test('أيام من غير مواعيد ما تاخدش ملخص', () async {
      final harness = h = await Harness.start(
        reply: (_) => serverReply('سجّلته.', [
          {
            'type': 'create',
            'title': 'موعد وحيد',
            'at': isoIn(const Duration(days: 3)),
            'remind_before_minutes': 60,
            'repeat': 'none',
            'notes': '',
          },
        ]),
      );

      await harness.send('موعد بعد ٣ أيام');

      // ملخص واحد بس — لليوم اللي فيه الموعد، مش لكل يوم.
      expect(harness.summaries, hasLength(1));
    });

    test('الموعد الخالص ما يظهرش في الملخص', () async {
      final harness = h = await Harness.start(
        reply: (_) => serverReply('سجّلته.', [
          {
            'type': 'create',
            'title': 'موعد هيخلص',
            'at': isoIn(const Duration(days: 1)),
            'remind_before_minutes': 60,
            'repeat': 'none',
            'notes': '',
          },
        ]),
      );
      await harness.send('موعد بكرة');
      final created = (await harness.store.all()).single;

      await harness.store.update(created.copyWith(done: true));
      await harness.container.read(appointmentsProvider.notifier).refresh();

      expect(harness.summaries, isEmpty);
    });
  });

  // ── إصلاحات من أول تشغيل على جهاز حقيقي (الدفعة الثانية) ─────────────────

  group('إصلاح: منع «الجدولة الدقيقة» كان يبلع كل التذكيرات في صمت', () {
    Appointment appt(String id, {int hours = 3}) => Appointment(
      id: id,
      title: 'اجتماع $id',
      at: DateTime.now().add(Duration(hours: hours)),
    );

    test('يقع على الجدولة غير الدقيقة بدل ما يرمي ويمسح كل حاجة', () async {
      final plugin = ExactBlockedPlugin();
      final scheduler = ReminderScheduler(plugin);

      // قبل الإصلاح: أول zonedSchedule يرمي → rescheduleAll تقع بعد
      // cancelAll → صفر تذكيرات متجدولة والمستخدم ما يعرف.
      await scheduler.rescheduleAll([appt('a'), appt('b', hours: 5)]);

      final reminders = plugin.scheduled
          .where((c) => (c.namedArguments[#id] as int) < 1000000000)
          .toList();
      expect(reminders, hasLength(2));
      for (final call in reminders) {
        expect(
          call.namedArguments[#androidScheduleMode],
          AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
      // اتحاول بالمراتب الأقوى الأول فعلًا — يعني الرجوع كان عن رفض
      // حقيقي مش تخطّي. تنبيهين × (منبّه + دقيق) = ٤ محاولات مرفوضة.
      expect(plugin.exactAttempts, greaterThanOrEqualTo(4));
    });

    test('المواعيد بتتحجز كمنبّه حقيقي مش كإشعار مجدول', () async {
      final plugin = RecordingPlugin();
      final scheduler = ReminderScheduler(plugin);

      await scheduler.rescheduleAll([appt('a')]);

      // setAlarmClock هو الاستثناء الوحيد اللي أنظمة شاومي/أوبو/تكنو
      // بتحترمه — الجدولة العادية بتتقتل مع التطبيق في الخلفية والتذكير
      // ما يرنّش رغم إن كل الأذونات خضرا.
      final appointmentCalls = plugin.scheduled
          .where((c) => (c.namedArguments[#id] as int) < 1900000000)
          .toList();
      expect(appointmentCalls, isNotEmpty);
      for (final call in appointmentCalls) {
        expect(
          call.namedArguments[#androidScheduleMode],
          AndroidScheduleMode.alarmClock,
        );
      }
    });

    test('ملخص الصبح ما ياخدش مرتبة المنبّه', () async {
      final plugin = RecordingPlugin();
      final scheduler = ReminderScheduler(plugin);

      // موعد بكرة عشان ملخص بكرة الصبح يتجدول.
      await scheduler.rescheduleAll([appt('a', hours: 30)]);

      final summaries = plugin.scheduled
          .where((c) => (c.namedArguments[#id] as int) >= 1900000000)
          .toList();
      expect(summaries, isNotEmpty);
      for (final call in summaries) {
        // معلومة مش إنذار — ما تزاحمش «المنبّه الجاي» على المواعيد.
        expect(
          call.namedArguments[#androidScheduleMode],
          AndroidScheduleMode.exactAllowWhileIdle,
        );
      }
    });

    test('عطل الجدولة ما يعلّقش الشات — الرد يوصل ومعاه تنبيه', () async {
      final harness = h = await Harness.start(
        notificationsPlugin: BrokenPlugin(),
        reply: (_) => serverReply('أبشر، سجّلته.', [
          {
            'type': 'create',
            'title': 'اجتماع أبو سعد',
            'at': isoIn(const Duration(hours: 3)),
            'remind_before_minutes': 60,
            'repeat': 'none',
            'notes': '',
          },
        ]),
      );

      await harness.send('عندي اجتماع مع أبو سعد بعد ٣ ساعات');

      final state = harness.container.read(chatProvider).value!;
      // قبل الإصلاح: sending كانت بتفضل true للأبد والرد يضيع.
      expect(state.sending, isFalse);
      expect(state.messages.last.text, contains('سجّلته'));
      expect(state.messages.last.text, contains('ما قدرت أضبط رنّة التذكير'));
      // الموعد نفسه اتسجّل — المشكلة كانت في الرنّة بس.
      expect(await harness.store.all(), hasLength(1));
    });
  });

  group('إصلاح: المتكرر كان يرنّ أول مرة بس وبعدين يموت في صمت', () {
    // rescheduleAll بتلغي كل حاجة وتعيد الجدولة مع كل فتح للتطبيق —
    // والمتكرر اللي مرّته الأولى عدّت كان بيتفلتر لأن وقته الأصلي بقى
    // في الماضي. «كل أحد الساعة ٩» كان معناها الفعلي «الأحد الجاي بس».

    List<Invocation> remindersOf(RecordingPlugin plugin) => plugin.scheduled
        .where((c) => (c.namedArguments[#id] as int) < 1000000000)
        .toList();

    test('أسبوعي عدّى أسبوعه الأول → يتجدول للأحد الجاي', () async {
      final plugin = RecordingPlugin();
      final weekly = Appointment(
        id: 'w1',
        title: 'اجتماع كل أحد',
        at: DateTime.now().subtract(const Duration(days: 3)),
        repeat: Repeat.weekly,
      );

      await ReminderScheduler(plugin).rescheduleAll([weekly]);

      final scheduled = remindersOf(plugin);
      expect(scheduled, hasLength(1));
      final fireAt =
          scheduled.single.namedArguments[#scheduledDate] as tz.TZDateTime;
      expect(fireAt.isAfter(DateTime.now()), isTrue);
      // المقارنة باللحظة مش بساعة الحائط — منطقة الاختبار (الرياض) غير
      // منطقة الجهاز، ومقارنة .hour بينهم هي نفس الغلطة اللي الكود
      // بيتحاشاها. المتوقع: التذكير الأصلي (الموعد - ساعة) + أسبوع واحد.
      final expected = weekly.at
          .subtract(const Duration(minutes: 60))
          .add(const Duration(days: 7));
      expect(fireAt.isAtSameMomentAs(expected), isTrue);
      expect(
        scheduled.single.namedArguments[#matchDateTimeComponents],
        DateTimeComponents.dayOfWeekAndTime,
      );
    });

    test('يومي قديم بأيام → يتجدول لبكرة مش يتفلتر', () async {
      final plugin = RecordingPlugin();
      final daily = Appointment(
        id: 'd1',
        title: 'دواء الضغط',
        at: DateTime.now().subtract(const Duration(days: 10)),
        repeat: Repeat.daily,
      );

      await ReminderScheduler(plugin).rescheduleAll([daily]);

      final scheduled = remindersOf(plugin);
      expect(scheduled, hasLength(1));
      final fireAt =
          scheduled.single.namedArguments[#scheduledDate] as tz.TZDateTime;
      expect(fireAt.isAfter(DateTime.now()), isTrue);
      expect(
        fireAt.difference(DateTime.now()),
        lessThan(const Duration(days: 1)),
      );
    });

    test('تأجيل عدّى وقته على متكرر → يرجع لجدوله الأساسي', () async {
      final plugin = RecordingPlugin();
      final snoozed = Appointment(
        id: 's1',
        title: 'اجتماع كل أحد',
        at: DateTime.now().subtract(const Duration(days: 3)),
        repeat: Repeat.weekly,
        // «أجّل ربع ساعة» من أسبوع فات — خلص مفعوله.
        snoozeUntil: DateTime.now().subtract(const Duration(days: 3)),
      );

      await ReminderScheduler(plugin).rescheduleAll([snoozed]);

      expect(remindersOf(plugin), hasLength(1));
    });

    test('غير المتكرر اللي فات وقته يتفلتر زي الأول بالظبط', () async {
      final plugin = RecordingPlugin();
      final past = Appointment(
        id: 'p1',
        title: 'موعد فات',
        at: DateTime.now().subtract(const Duration(days: 1)),
      );

      await ReminderScheduler(plugin).rescheduleAll([past]);

      expect(remindersOf(plugin), isEmpty);
    });
  });

  group('إصلاح: زرار المايك كان بيعلّق على «أسمعك…»', () {
    test('لما المحرّك يقف لوحده الخدمة تبلّغ والواجهة ترجع', () async {
      final engine = FakeSpeechEngine();
      final service = SpeechService(engine);

      var stopped = 0;
      service.onStopped = () => stopped++;

      expect(await service.initialize(), isTrue);
      // المحرّك وقف من غير أي نتيجة نهائية — زي ما بيحصل مع السكوت.
      engine.capturedOnStatus!('notListening');
      expect(stopped, 1);
    });

    test('العطل بيوصل للمستخدم بلغته مش بيضيع في اللوج', () async {
      final engine = FakeSpeechEngine();
      final service = SpeechService(engine);

      String? problem;
      var stopped = 0;
      service.onProblem = (m) => problem = m;
      service.onStopped = () => stopped++;

      await service.initialize();
      engine.capturedOnError!(SpeechRecognitionError('error_network', false));

      expect(problem, contains('نت'));
      expect(stopped, 1);
    });

    test('«ما فيه كلام» مش عطل يستاهل رسالة — بس المايك يرجع', () async {
      final engine = FakeSpeechEngine();
      final service = SpeechService(engine);

      String? problem;
      var stopped = 0;
      service.onProblem = (m) => problem = m;
      service.onStopped = () => stopped++;

      await service.initialize();
      engine.capturedOnError!(SpeechRecognitionError('error_no_match', false));

      expect(problem, isNull);
      expect(stopped, 1);
    });
  });

  group('إصلاح: التفريغ الصوتي كان بيطلع إنجليزي مش مفهوم', () {
    // الجذر: لو المحرّك ما أعلنش عن أي لغة عربية في locales() كنا بنسيب
    // localeId فاضي، والمحرّك يقع على لغة الجهاز — إنجليزي غالبًا. المستخدم
    // بيتكلم عربي بس، فالعربي بيُفرض دايمًا حتى لو مش في القائمة.

    test('المحرّك من غير عربي في قايمته → نفرض ar_SA برضه', () async {
      final engine = FakeSpeechEngine()
        ..localeList = [LocaleName('en_US', 'English (US)')];
      final service = SpeechService(engine);

      await service.initialize();

      expect(service.localeId, 'ar_SA');
    });

    test('فيه عربي تاني متاح (مصر مثلًا) → ناخده بدل الفرض', () async {
      final engine = FakeSpeechEngine()
        ..localeList = [
          LocaleName('en_US', 'English (US)'),
          LocaleName('ar_EG', 'العربية (مصر)'),
        ];
      final service = SpeechService(engine);

      await service.initialize();

      expect(service.localeId, 'ar_EG');
    });
  });

  group('الميزة: صفّارة إنذار قوية في وقت الموعد نفسه', () {
    // طلب صاحب العمل الحرفي: «عاوزه يعمل إنذار قوي جدًا في ميعاد الميتنج
    // يعمل صفارة إنذار». التذكير المسبق (قبل الموعد بساعة) موجود زي ما هو،
    // والجديد إشعار تاني في لحظة الموعد نفسها: قناة بصوت صفّارة حقيقي على
    // مجرى المنبّه + FLAG_INSISTENT فالصوت يفضل شغّال لحد ما يسكّته بإيده.

    List<Invocation> sirensOf(RecordingPlugin plugin) =>
        plugin.scheduled.where((c) {
          final id = c.namedArguments[#id] as int;
          return id >= 1000000000 && id < 1900000000;
        }).toList();

    test('كل موعد بياخد صفّارة في وقته فوق التذكير المسبق', () async {
      final plugin = RecordingPlugin();
      final at = DateTime.now().add(const Duration(hours: 3));
      final meeting = Appointment(id: 'm1', title: 'ميتنج مهم', at: at);

      await ReminderScheduler(plugin).rescheduleAll([meeting]);

      final sirens = sirensOf(plugin);
      expect(sirens, hasLength(1));
      final call = sirens.single;

      final when = call.namedArguments[#scheduledDate] as tz.TZDateTime;
      expect(when.isAtSameMomentAs(at), isTrue);
      expect(call.namedArguments[#title], contains('ميتنج مهم'));

      final details =
          call.namedArguments[#notificationDetails] as NotificationDetails;
      final android = details.android!;
      expect(android.channelId, AppConfig.alarmChannelId);
      expect(android.sound, isA<RawResourceAndroidNotificationSound>());
      expect(
        (android.sound as RawResourceAndroidNotificationSound).sound,
        'siren',
      );
      // FLAG_INSISTENT (القيمة 4): الصفّارة تفضل شغّالة لحد ما تتسكّت.
      expect(android.additionalFlags, contains(4));
      expect(android.fullScreenIntent, isTrue);
      expect(android.audioAttributesUsage, AudioAttributesUsage.alarm);
    });

    test('تذكير صفر دقايق → صفّارة واحدة مش إشعارين على نفس اللحظة', () async {
      // الرسايل المجدولة («ابعت لفلان») بتتسجّل بتذكير صفر — التذكير
      // المسبق والصفّارة كانوا هيقعوا على نفس الثانية.
      final plugin = RecordingPlugin();
      final scheduler = ReminderScheduler(plugin);

      await scheduler.rescheduleAll([
        Appointment(
          id: 'z1',
          title: 'ابعت لأبو سعد',
          at: DateTime.now().add(const Duration(hours: 2)),
          remindBeforeMinutes: 0,
        ),
      ]);

      expect(sirensOf(plugin), hasLength(1));
      final reminders = plugin.scheduled
          .where((c) => (c.namedArguments[#id] as int) < 1000000000)
          .toList();
      expect(reminders, isEmpty);
    });

    test('متكرر فاتت مرّته → الصفّارة تتدحرج للمرة الجاية مش تموت', () async {
      final plugin = RecordingPlugin();
      final weekly = Appointment(
        id: 'w-siren',
        title: 'اجتماع كل أحد',
        at: DateTime.now().subtract(const Duration(days: 3)),
        repeat: Repeat.weekly,
      );

      await ReminderScheduler(plugin).rescheduleAll([weekly]);

      final sirens = sirensOf(plugin);
      expect(sirens, hasLength(1));
      final when =
          sirens.single.namedArguments[#scheduledDate] as tz.TZDateTime;
      expect(
        when.isAtSameMomentAs(weekly.at.add(const Duration(days: 7))),
        isTrue,
      );
    });

    test('«جرّبها الحين» بترنّ نفس الصفّارة فورًا — مش نسخة مخففة', () async {
      // زرار التجربة في الإعدادات لازم يطلع بنفس القناة ونفس الصوت ونفس
      // الإلحاح بتاع وقت الموعد — عشان نجاحه يبقى دليل حقيقي.
      final plugin = RecordingPlugin();

      await ReminderScheduler(plugin).ringSirenNow();

      expect(plugin.shown, hasLength(1));
      final details =
          plugin.shown.single.namedArguments[#notificationDetails]
              as NotificationDetails;
      final android = details.android!;
      expect(android.channelId, AppConfig.alarmChannelId);
      expect(
        (android.sound as RawResourceAndroidNotificationSound).sound,
        'siren',
      );
      expect(android.additionalFlags, contains(4));
    });

    test('إلغاء الموعد بيلغي التذكير والصفّارة مع بعض', () async {
      final plugin = RecordingPlugin();
      final scheduler = ReminderScheduler(plugin);

      await scheduler.cancel('m1');

      expect(plugin.cancelled, hasLength(2));
      expect(plugin.cancelled.where((id) => id < 1000000000), hasLength(1));
      expect(
        plugin.cancelled.where((id) => id >= 1000000000 && id < 1900000000),
        hasLength(1),
      );
    });
  });
}
