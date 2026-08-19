import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/providers.dart';

/// صندوق الكتابة + زرار المايك.
///
/// الصوت بيكتب في نفس صندوق النص بدل ما يبعت على طول — كده المستخدم يقدر
/// يصحّح كلمة غلط قبل ما يرسل، وده بيحصل كتير مع الأسماء.
class Composer extends ConsumerStatefulWidget {
  const Composer({super.key, required this.enabled, required this.onSend});

  final bool enabled;
  final void Function(String text) onSend;

  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  bool _listening = false;

  /// نبضة زرار المايك وهو بيسمع — إشارة مرئية إن الجهاز فعلًا بيسجّل.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  /// النص اللي كان مكتوب قبل ما الاستماع يبدأ. نتيجة الصوت بتتزاد عليه بدل
  /// ما تمسحه.
  String _textBeforeListening = '';

  @override
  void dispose() {
    _pulse.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setListening(bool value) {
    if (!mounted) return;
    setState(() => _listening = value);
    if (value) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    _controller.clear();
    widget.onSend(text);
    _focus.unfocus();
  }

  Future<void> _toggleMic() async {
    final speech = ref.read(speechServiceProvider);

    if (_listening) {
      await speech.stop();
      _setListening(false);
      return;
    }

    // المحرّك بيقف لوحده كتير (سكوت، مهلة، عطل) ومش مضمون توصل نتيجة
    // نهائية — الإشارات دي هي اللي بترجّع زرار المايك لحالته بدل ما يفضل
    // شكله «بيسمع» وهو واقف.
    speech.onStopped = () {
      if (mounted && _listening) _setListening(false);
    };
    speech.onProblem = (message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    };

    if (!await speech.initialize()) {
      if (!mounted) return;
      // الرسالة بتفرّق بين «الإذن مقفول» و«الجهاز مافيهوش محرّك» — الاتنين
      // ليهم حل مختلف تمامًا، ورسالة واحدة عامة كانت بتسيب المستخدم واقف.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(speech.lastProblem.message),
            duration: const Duration(seconds: 6),
          ),
        );
      return;
    }

    _textBeforeListening = _controller.text;
    _setListening(true);

    await speech.start(
      onResult: (text, isFinal) {
        if (!mounted) return;
        final prefix = _textBeforeListening.isEmpty
            ? ''
            : '${_textBeforeListening.trimRight()} ';
        _controller
          ..text = '$prefix$text'
          ..selection = TextSelection.collapsed(
            offset: _controller.text.length,
          );
        if (isFinal) _setListening(false);
      },
    );
  }

  Widget _micButton(ColorScheme scheme) {
    if (!_listening) {
      return IconButton(
        tooltip: 'تكلّم',
        onPressed: widget.enabled ? _toggleMic : null,
        icon: Icon(Icons.mic_none, color: scheme.primary),
      );
    }
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_pulse.value);
        return IconButton(
          tooltip: 'إيقاف',
          onPressed: _toggleMic,
          style: IconButton.styleFrom(
            backgroundColor: scheme.errorContainer.withValues(
              alpha: 0.45 + 0.55 * t,
            ),
          ),
          icon: Transform.scale(
            scale: 1 + 0.12 * t,
            child: Icon(Icons.mic, color: scheme.error),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                enabled: widget.enabled,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: _listening ? 'أسمعك…' : 'اكتب أو تكلّم…',
                  suffixIcon: _micButton(scheme),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, value, _) {
                final canSend = widget.enabled && value.text.trim().isNotEmpty;
                return AnimatedScale(
                  scale: canSend ? 1 : 0.88,
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  child: IconButton.filled(
                    onPressed: canSend ? _send : null,
                    icon: const Icon(Icons.arrow_upward),
                    tooltip: 'إرسال',
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
