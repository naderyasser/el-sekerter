import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../api/api_client.dart';
import '../models/appointment.dart';
import '../models/chat_message.dart';
import '../models/server_action.dart';
import 'appointments_controller.dart';
import 'providers.dart';

class ChatState {
  const ChatState({this.messages = const [], this.sending = false, this.error});

  final List<ChatMessage> messages;
  final bool sending;

  /// خطأ آخر إرسال. بيتعرض كـsnackbar ويتمسح مع أول محاولة جديدة.
  final String? error;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? sending,
    String? error,
    bool clearError = false,
  }) => ChatState(
    messages: messages ?? this.messages,
    sending: sending ?? this.sending,
    error: clearError ? null : (error ?? this.error),
  );
}

class ChatController extends AsyncNotifier<ChatState> {
  @override
  Future<ChatState> build() async {
    final messages = await ref.read(chatStoreProvider).recent();
    return ChatState(messages: messages);
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final current = state.value ?? const ChatState();
    if (current.sending) return;

    final chatStore = ref.read(chatStoreProvider);

    // اعرض رسالة المستخدم على طول — الشات لازم يحس بإنه بيرد بسرعة حتى لو
    // السيرفر بيفكّر.
    final sent = await chatStore.add(
      ChatMessage(
        id: 0,
        sender: Sender.user,
        text: trimmed,
        at: DateTime.now(),
      ),
    );

    // التاريخ المبعوت للسيرفر لازم يكون قبل الرسالة الجديدة — الرسالة نفسها
    // بتتبعت في حقل `message` لوحدها.
    final history = current.messages;

    state = AsyncValue.data(
      current.copyWith(
        messages: [...current.messages, sent],
        sending: true,
        clearError: true,
      ),
    );

    try {
      final response = await ref
          .read(apiClientProvider)
          .chat(
            message: trimmed,
            appointments: await _contextAppointments(),
            history: history,
            // اسم IANA («Asia/Riyadh») مش الاختصار — timeZoneName بيرجّع
            // «GMT+03:00» والموديل ما يعرف منه البلد ولا مواقيت الصلاة.
            timezone: (await FlutterTimezone.getLocalTimezone()).identifier,
          );

      // الرسالة المجدولة موعد مو إرسال فوري — بتتنفّذ في وقتها.
      final scheduled = response.actions
          .where((a) => a.isScheduledMessage)
          .toList();
      final immediate = response.actions
          .where((a) => !a.isScheduledMessage)
          .toList();

      if (immediate.isNotEmpty || scheduled.isNotEmpty) {
        await ref.read(appointmentStoreProvider).applyActions([
          ...immediate,
          ...scheduled.map(_asAppointment),
        ]);
        // إعادة الجدولة جزء من refresh — أي ميعاد اتغيّر لازم تذكيره يتظبّط.
        await ref.read(appointmentsProvider.notifier).refresh();
      }

      // الاتصال والإرسال الفوري بيتنفّذوا على الجهاز، ونتيجتهم بتتعرض في الشات
      // عشان صاحب العمل يعرف إيش صار — خصوصًا لو الاسم طابق أكثر من واحد.
      final notes = <String>[];
      for (final action in immediate) {
        final outcome = await ref.read(actionRunnerProvider).run(action);
        if (outcome != null) notes.add(outcome.message);
      }

      final reply = await chatStore.add(
        ChatMessage(
          id: 0,
          sender: Sender.secretary,
          text:
              [
                if (response.reply.isNotEmpty) response.reply,
                ...notes,
              ].join('\n').trim().isEmpty
              ? 'تم.'
              : [
                  if (response.reply.isNotEmpty) response.reply,
                  ...notes,
                ].join('\n'),
          at: DateTime.now(),
        ),
      );

      final latest = state.value ?? current;
      state = AsyncValue.data(
        latest.copyWith(messages: [...latest.messages, reply], sending: false),
      );
    } on ApiException catch (e) {
      // رسالة المستخدم بتفضل معلّمة بإنها فشلت عشان يقدر يعيد إرسالها.
      await chatStore.setFailed(sent.id, failed: true);

      final latest = state.value ?? current;
      state = AsyncValue.data(
        latest.copyWith(
          messages: [
            for (final m in latest.messages)
              if (m.id == sent.id) m.copyWith(failed: true) else m,
          ],
          sending: false,
          error: e.message,
        ),
      );
    }
  }

  /// مواعيد السكرتير + أحداث تقويم الجهاز في الأسبوعين الجايين، عشان يقدر
  /// يجاوب «أنا فاضي الخميس؟» من واقع جدوله كله مو من مواعيده هو بس.
  Future<List<Appointment>> _contextAppointments() async {
    final mine = await ref.read(appointmentStoreProvider).upcoming();
    final now = DateTime.now();
    final events = await ref
        .read(calendarServiceProvider)
        .eventsBetween(now, now.add(const Duration(days: 14)));
    return [...mine, ...events]..sort((a, b) => a.at.compareTo(b.at));
  }

  /// يعيد إرسال رسالة فشلت.
  Future<void> retry(ChatMessage message) async {
    final current = state.value ?? const ChatState();
    await ref.read(chatStoreProvider).setFailed(message.id, failed: false);
    state = AsyncValue.data(
      current.copyWith(
        messages: current.messages.where((m) => m.id != message.id).toList(),
      ),
    );
    await send(message.text);
  }

  void clearError() {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(current.copyWith(clearError: true));
  }

  Future<void> clearHistory() async {
    await ref.read(chatStoreProvider).clear();
    state = const AsyncValue.data(ChatState());
  }
}

/// رسالة مجدولة بتتخزّن كموعد: الإشعار يرنّ في وقتها، وضغطة عليه تفتح
/// واتساب والنص جاهز. ما فيه أي منصّة تسمح بإرسال صامت.
ServerAction _asAppointment(ServerAction message) => ServerAction(
  type: ActionType.create,
  title: 'ابعت لـ${message.who}',
  at: message.at,
  remindBeforeMinutes: 0,
  repeat: Repeat.none,
  notes: message.text,
);

final chatProvider = AsyncNotifierProvider<ChatController, ChatState>(
  ChatController.new,
);
