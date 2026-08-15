import 'package:flutter/material.dart';

import '../../../core/arabic.dart';
import '../../../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final ChatMessage message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.sender == Sender.user;

    final background = isUser
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final foreground = isUser ? scheme.onPrimaryContainer : scheme.onSurface;

    return Align(
      alignment: isUser
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: isUser
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isUser ? 18 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 18),
                  ),
                ),
                child: Text(
                  message.text,
                  style: TextStyle(color: foreground, height: 1.45),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 3, right: 6, left: 6),
                child: message.failed
                    ? _FailedRow(onRetry: onRetry)
                    : Text(
                        ArabicDate.time(message.at),
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FailedRow extends StatelessWidget {
  const _FailedRow({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 14, color: error),
        const SizedBox(width: 4),
        Text(
          'ما وصلت',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: error),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: onRetry,
          child: Text(
            'أعد الإرسال',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: error,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}
