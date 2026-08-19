import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/arabic.dart';
import '../../models/chat_message.dart';
import '../../state/chat_controller.dart';
import 'widgets/composer.dart';
import 'widgets/message_bubble.dart';
import 'widgets/secretary_avatar.dart';

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

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// رسايل من نفس الطرف وقريبة في الوقت بتتعرض كمجموعة واحدة.
  static bool _sameGroup(ChatMessage a, ChatMessage b) =>
      a.sender == b.sender &&
      _sameDay(a.at, b.at) &&
      b.at.difference(a.at).inMinutes < 5;

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
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SecretaryAvatar(size: 28),
            SizedBox(width: 8),
            Text('السكرتير'),
          ],
        ),
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
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      itemCount: state.messages.length,
                      itemBuilder: (context, index) {
                        final messages = state.messages;
                        final message = messages[index];
                        final prev = index > 0 ? messages[index - 1] : null;
                        final next = index < messages.length - 1
                            ? messages[index + 1]
                            : null;

                        final bubble = MessageBubble(
                          message: message,
                          isFirstInGroup:
                              prev == null || !_sameGroup(prev, message),
                          isLastInGroup:
                              next == null || !_sameGroup(message, next),
                          onRetry: () =>
                              ref.read(chatProvider.notifier).retry(message),
                        );

                        if (prev != null && _sameDay(prev.at, message.at)) {
                          return bubble;
                        }
                        return Column(
                          children: [
                            _DaySeparator(at: message.at),
                            bubble,
                          ],
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

/// فاصل «اليوم» / «أمس» / اسم اليوم بين رسايل الأيام المختلفة.
class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.at});

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          ArabicDate.day(at),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _EmptyChat extends ConsumerWidget {
  const _EmptyChat();

  static const _examples = [
    'ذكّرني بموعد الدكتور بكرة الساعة ٥ ونص',
    'عندي اجتماع مع المورّد الخميس بعد العصر',
    'وش عندي بكرة؟',
    'ألغِ موعد الدكتور',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SecretaryAvatar(size: 84),
            const SizedBox(height: 20),
            Text(
              'أهلًا، أنا سكرتيرك الخاص',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'قل لي مواعيدك وأنا أسجّلها وأذكّرك فيها.\nجرّب وحدة من دول:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // الأمثلة أزرار حقيقية — ضغطة واحدة بتبعت الجملة على طول،
            // أسرع طريقة يجرّب بيها مستخدم جديد من غير ما يكتب.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final example in _examples)
                  ActionChip(
                    label: Text(example),
                    labelStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                    ),
                    backgroundColor: scheme.surfaceContainerLow,
                    side: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    onPressed: () =>
                        ref.read(chatProvider.notifier).send(example),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// «بيكتب…» — ثلاث نقط بتتنفس بالتناوب جوّه فقاعة زي فقاعات السكرتير.
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 12, bottom: 8, top: 2),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const SecretaryAvatar(size: 26),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: const BorderRadiusDirectional.only(
                  topStart: Radius.circular(18),
                  topEnd: Radius.circular(18),
                  bottomEnd: Radius.circular(18),
                  bottomStart: Radius.circular(4),
                ),
              ),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 5),
                      _dot(i, scheme),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(int i, ColorScheme scheme) {
    final phase = _controller.value * 2 * math.pi - i * 0.9;
    final lift = (math.sin(phase) + 1) / 2;
    return Transform.translate(
      offset: Offset(0, -3 * lift),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.35 + 0.55 * lift),
        ),
      ),
    );
  }
}
