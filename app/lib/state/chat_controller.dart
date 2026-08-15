import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/chat_message.dart';
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
            appointments: await ref.read(appointmentStoreProvider).upcoming(),
            history: history,
            timezone: DateTime.now().timeZoneName,
          );

      if (response.actions.isNotEmpty) {
        await ref.read(appointmentStoreProvider).applyActions(response.actions);
        // إعادة الجدولة جزء من refresh — أي ميعاد اتغيّر لازم تذكيره يتظبّط.
        await ref.read(appointmentsProvider.notifier).refresh();
      }

      final reply = await chatStore.add(
        ChatMessage(
          id: 0,
          sender: Sender.secretary,
          text: response.reply.isEmpty ? 'تم.' : response.reply,
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

final chatProvider = AsyncNotifierProvider<ChatController, ChatState>(
  ChatController.new,
);
