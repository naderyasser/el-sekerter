import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/chat_controller.dart';
import 'widgets/composer.dart';
import 'widgets/message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    // بعد الفريم عشان القايمة تكون اتبنت بالرسالة الجديدة.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);

    ref.listen(chatProvider, (previous, next) {
      final error = next.value?.error;
      if (error != null && error != previous?.value?.error) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error)));
        ref.read(chatProvider.notifier).clearError();
      }
      if (next.value?.messages.length != previous?.value?.messages.length) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('السكرتير'),
        actions: [
          IconButton(
            tooltip: 'امسح المحادثة',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => _confirmClear(context),
          ),
        ],
      ),
      body: chat.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('ما قدرت أفتح المحادثة.\n$e')),
        data: (state) => Column(
          children: [
            Expanded(
              child: state.messages.isEmpty
                  ? const _EmptyChat()
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      itemCount: state.messages.length,
                      itemBuilder: (context, index) {
                        final message = state.messages[index];
                        return MessageBubble(
                          message: message,
                          onRetry: () =>
                              ref.read(chatProvider.notifier).retry(message),
                        );
                      },
                    ),
            ),
            if (state.sending) const _TypingIndicator(),
            Composer(
              enabled: !state.sending,
              onSend: (text) => ref.read(chatProvider.notifier).send(text),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('امسح المحادثة؟'),
        content: const Text(
          'بتنمسح الرسايل بس. مواعيدك المسجّلة تبقى زي ما هي.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لا'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('امسح'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(chatProvider.notifier).clearHistory();
    }
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  static const _examples = [
    'ذكّرني بموعد الدكتور بكرة الساعة ٥ ونص',
    'عندي اجتماع مع المورّد الخميس بعد العصر',
    'وش عندي بكرة؟',
    'ألغِ موعد الدكتور',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 56,
              color: scheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 20),
            Text(
              'قل لي مواعيدك وأنا أذكّرك فيها',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            for (final example in _examples)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '«$example»',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 24, bottom: 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text('يكتب…', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
