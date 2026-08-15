import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sekerter/core/arabic.dart';
import 'package:sekerter/models/appointment.dart';
import 'package:sekerter/models/chat_message.dart';
import 'package:sekerter/models/server_action.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('ar'));

  group('Appointment', () {
    final at = DateTime(2026, 8, 16, 17, 30);

    test('remindAt يطرح مدة التذكير من وقت الموعد', () {
      final appointment = Appointment(
        id: 'a1',
        title: 'موعد الدكتور',
        at: at,
        remindBeforeMinutes: 90,
      );
      expect(appointment.remindAt, DateTime(2026, 8, 16, 16, 0));
    });

    test('الحفظ UTC والقراءة محلي — الموعد ما يزحف', () {
      final appointment = Appointment(id: 'a1', title: 'اجتماع', at: at);
      final restored = Appointment.fromRow(appointment.toRow());
      expect(restored.at, at);
      expect(restored.title, 'اجتماع');
    });

    test('toApi يرسل الوقت بالتوقيت المحلي بفرقه', () {
      final appointment = Appointment(id: 'a1', title: 'اجتماع', at: at);
      // الموديل لازم يشوف نفس الساعة اللي المستخدم شايفها.
      expect(appointment.toApi()['at'], at.toIso8601String());
    });

    test('repeat غير معروف يرجع none بدل ما يرمي', () {
      expect(Repeat.parse('hourly'), Repeat.none);
      expect(Repeat.parse(null), Repeat.none);
      expect(Repeat.parse('weekly'), Repeat.weekly);
    });
  });

  group('ServerAction', () {
    test('create كامل ينفّذ', () {
      final action = ServerAction.fromJson({
        'type': 'create',
        'title': 'موعد الدكتور',
        'at': '2026-08-16T17:30:00+03:00',
        'remind_before_minutes': 60,
        'repeat': 'none',
        'notes': '',
      });
      expect(action.type, ActionType.create);
      expect(action.isApplicable, isTrue);
      expect(action.title, 'موعد الدكتور');
    });

    test('create بدون وقت ما ينفّذ', () {
      final action = ServerAction.fromJson({'type': 'create', 'title': 'موعد'});
      expect(action.isApplicable, isFalse);
    });

    test('نوع أمر مجهول من سيرفر أحدث يتتجاهل بدل ما يوقّع التطبيق', () {
      final action = ServerAction.fromJson({'type': 'snooze', 'id': 'a1'});
      expect(action.type, ActionType.unknown);
      expect(action.isApplicable, isFalse);
    });

    test('تاريخ بايظ يتتجاهل بدل ما يرمي', () {
      final action = ServerAction.fromJson({
        'type': 'create',
        'title': 'موعد',
        'at': 'بكرة الساعة خمسة',
      });
      expect(action.at, isNull);
      expect(action.isApplicable, isFalse);
    });

    test('null في التعديل معناها «سيبه زي ما هو»', () {
      final action = ServerAction.fromJson({
        'type': 'update',
        'id': 'a1',
        'title': null,
        'at': '2026-08-17T10:00:00+03:00',
        'remind_before_minutes': null,
        'repeat': null,
        'notes': null,
      });
      expect(action.isApplicable, isTrue);
      expect(action.title, isNull);
      expect(action.at, isNotNull);
    });

    test('ChatResponse يفلتر الأوامر الناقصة', () {
      final response = ChatResponse.fromJson({
        'reply': 'تم.',
        'actions': [
          {'type': 'delete', 'id': 'a1'},
          {'type': 'delete'}, // بدون id — يتفلتر
          {'type': 'create', 'title': 'x'}, // بدون at — يتفلتر
        ],
      });
      expect(response.reply, 'تم.');
      expect(response.actions.length, 1);
      expect(response.actions.single.type, ActionType.delete);
    });

    test('رد بدون actions يشتغل عادي', () {
      final response = ChatResponse.fromJson({'reply': 'عندك موعدين بكرة.'});
      expect(response.actions, isEmpty);
    });
  });

  group('ChatMessage', () {
    test('toApi يستخدم content زي ما السيرفر متوقّع', () {
      final message = ChatMessage(
        id: 1,
        sender: Sender.user,
        text: 'ذكّرني بالدكتور',
        at: DateTime.now(),
      );
      expect(message.toApi(), {'role': 'user', 'content': 'ذكّرني بالدكتور'});
    });

    test('رد السكرتير دوره assistant', () {
      final message = ChatMessage(
        id: 2,
        sender: Sender.secretary,
        text: 'تم.',
        at: DateTime.now(),
      );
      expect(message.toApi()['role'], 'assistant');
    });
  });

  group('ArabicDate', () {
    final now = DateTime(2026, 8, 15, 14, 30);

    test('الأيام القريبة بأسمائها', () {
      expect(ArabicDate.day(DateTime(2026, 8, 15, 20), now: now), 'اليوم');
      expect(ArabicDate.day(DateTime(2026, 8, 16, 9), now: now), 'بكرة');
      expect(ArabicDate.day(DateTime(2026, 8, 17, 9), now: now), 'عقب بكرة');
      expect(ArabicDate.day(DateTime(2026, 8, 14, 9), now: now), 'أمس');
    });

    test('الوقت بصيغة ١٢ ساعة مع ص/م', () {
      expect(ArabicDate.time(DateTime(2026, 8, 16, 17, 30)), contains('م'));
      expect(ArabicDate.time(DateTime(2026, 8, 16, 9, 0)), contains('ص'));
    });

    test('الوقت النسبي بالسعودي', () {
      expect(
        ArabicDate.relative(DateTime(2026, 8, 15, 16, 30), now: now),
        'باقي ساعتين',
      );
      expect(
        ArabicDate.relative(DateTime(2026, 8, 17, 14, 30), now: now),
        'باقي يومين',
      );
      expect(ArabicDate.relative(DateTime(2026, 8, 14), now: now), 'فات');
    });

    test('وصف التذكير', () {
      expect(ArabicDate.reminderLead(60), 'التذكير قبله بساعة');
      expect(ArabicDate.reminderLead(120), 'التذكير قبله بساعتين');
      expect(ArabicDate.reminderLead(1440), 'التذكير قبله بيوم');
      expect(ArabicDate.reminderLead(0), 'التذكير في وقت الموعد');
      expect(ArabicDate.reminderLead(15), 'التذكير قبله بـ 15 دقيقة');
    });
  });
}
