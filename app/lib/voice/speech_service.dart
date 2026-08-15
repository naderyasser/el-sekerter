import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// تفريغ الكلام لنص.
///
/// بيستخدم التعرّف المدمج في نظام التشغيل (SpeechRecognizer على أندرويد،
/// SFSpeechRecognizer على آيفون) — مجاني ومن غير خدمة خارجية ولا مفاتيح، وأهم
/// حاجة إن صوت المستخدم مبيخرجش لأي طرف تالت.
class SpeechService {
  SpeechService([SpeechToText? speech]) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;

  /// العربي السعودي. لو الجهاز مفهوش، بنقع على أقرب عربي متاح.
  static const String _preferredLocale = 'ar_SA';

  bool _available = false;
  String? _localeId;

  bool get isListening => _speech.isListening;

  /// بيرجّع false لو الجهاز مبيدعمش التفريغ أو المستخدم رفض إذن المايك.
  Future<bool> initialize() async {
    if (_available) return true;

    _available = await _speech.initialize(
      onError: (e) => debugPrint('speech error: ${e.errorMsg}'),
      // بنطفّي الصوت المزعج اللي بيطلع مع بداية الاستماع على بعض الأجهزة.
      options: [SpeechToText.androidIntentLookup],
    );

    if (_available) _localeId = await _resolveLocale();
    return _available;
  }

  Future<String?> _resolveLocale() async {
    final locales = await _speech.locales();
    for (final id in [_preferredLocale, 'ar-SA']) {
      final match = locales.where((l) => l.localeId == id);
      if (match.isNotEmpty) return match.first.localeId;
    }
    // أي عربي أحسن من الافتراضي (اللي غالبًا إنجليزي).
    final anyArabic = locales.where(
      (l) => l.localeId.startsWith('ar_') || l.localeId.startsWith('ar-'),
    );
    return anyArabic.isNotEmpty ? anyArabic.first.localeId : null;
  }

  /// يبدأ الاستماع. [onResult] بتتنده مع كل تحديث — النتيجة النهائية بيبقى
  /// معاها [isFinal] = true.
  Future<void> start({
    required void Function(String text, bool isFinal) onResult,
  }) async {
    if (!await initialize()) return;

    await _speech.listen(
      onResult: (result) =>
          onResult(result.recognizedWords, result.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: _localeId,
        partialResults: true,
        // المستخدم بيملي ميعاد، مش بيدردش — كلامه بيخلص بسرعة.
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        // يقف بعد ٣ ثواني سكوت، وبحد أقصى ٣٠ ثانية للجلسة كلها.
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 30),
      ),
    );
  }

  Future<void> stop() => _speech.stop();

  Future<void> cancel() => _speech.cancel();
}
