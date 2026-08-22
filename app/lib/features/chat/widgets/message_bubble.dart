import 'package:flutter/material.dart';

import '../../../core/arabic.dart';
import '../../../models/chat_message.dart';
import 'secretary_avatar.dart';

/// فقاعة رسالة واحدة. الرسايل المتتالية من نفس الطرف بتتجمّع: الذيل
/// والأفاتار والوقت على آخر رسالة في المجموعة بس، والمسافة بينها أصغر.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.onRetry,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
  });

  final ChatMessage message;
  final VoidCallback onRetry;
  final bool isFirstInGroup;
  final bool isLastInGroup;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.sender == Sender.user;

    // رسالة صاحب العمل باللون الأساسي الكامل — التمييز بين الطرفين لازم
    // يبان من متر، مش درجتين متقاربين من نفس الرمادي.
    final background = isUser ? scheme.primary : scheme.surfaceContainerHigh;
    final foreground = isUser ? scheme.onPrimary : scheme.onSurface;

    // الزوايا اتجاهية عشان الذيل يطلع على الجنب الصح في RTL: فقاعة
    // السكرتير عند البداية وذيلها هناك، وفقاعة صاحب العمل عند النهاية.
    const round = Radius.circular(18);
    const joined = Radius.circular(6);
    const tail = Radius.circular(4);
    final radius = isUser
        ? BorderRadiusDirectional.only(
            topStart: round,
            bottomStart: round,
            topEnd: isFirstInGroup ? round : joined,
            bottomEnd: isLastInGroup ? tail : joined,
          )
        : BorderRadiusDirectional.only(
            topEnd: round,
            bottomEnd: round,
            topStart: isFirstInGroup ? round : joined,
            bottomStart: isLastInGroup ? tail : joined,
          );

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        border: isUser
            ? null
            : Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Text(
        message.text,
        style: TextStyle(color: foreground, height: 1.45),
      ),
    );

    final content = Column(
      crossAxisAlignment: isUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        bubble,
        // الوقت مرة واحدة تحت آخر فقاعة — إلا لو الرسالة فشلت فلازم
        // علامة الإعادة تبان مهما كان مكانها.
        if (message.failed || isLastInGroup)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 3, start: 6, end: 6),
            child: message.failed
                ? _FailedRow(onRetry: onRetry)
                : Text(
                    ArabicDate.time(message.at),
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
          ),
      ],
    );

    final constrained = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      child: content,
    );

    return Align(
      alignment: isUser
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Padding(
        padding: EdgeInsets.only(bottom: isLastInGroup ? 8 : 2),
        child: isUser
            ? constrained
            : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // الأفاتار مرة واحدة عند آخر رسالة في المجموعة، والباقي
                  // بياخد نفس العرض عشان الفقاعات تفضل متحاذية.
                  if (isLastInGroup)
                    const SecretaryAvatar(size: 26)
                  else
                    const SizedBox(width: 26),
                  const SizedBox(width: 6),
                  Flexible(child: constrained),
                ],
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
