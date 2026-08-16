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

  /// الاستماع وقف — سواء المستخدم سكت، أو المهلة خلصت، أو حصل عطل.
  /// الواجهة لازم تسمع ده عشان زرار المايك ما يفضلش شكله «بيسمع» وهو واقف:
  /// نتيجة نهائية (isFinal) مش مضمونة توصل أصلًا — لو ما فيش كلام اتلقط،
  /// المحرّك بيقفل من غير أي onResult، وده كان بيسيب المايك معلّق للأبد.
  void Function()? onStopped;

  /// عطل بلغة المستخدم — يتعرض له بدل ما يضيع في اللوج.
  void Function(String message)? onProblem;

  bool get isListening => _speech.isListening;

  /// بيرجّع false لو الجهاز مبيدعمش التفريغ أو المستخدم رفض إذن المايك.
  Future<bool> initialize() async {
    if (_available) return true;

    _available = await _speech.initialize(
      onError: (e) {
        debugPrint('speech error: ${e.errorMsg}');
        // «ما سمعتش حاجة» مش عطل يستاهل رسالة — بيحصل مع أي سكتة.
        if (e.errorMsg != 'error_no_match' &&
            e.errorMsg != 'error_speech_timeout') {
          onProblem?.call(_describe(e.errorMsg));
        }
        onStopped?.call();
      },
      onStatus: (status) {
        // المحرّك بيبعت notListening لما يقف لأي سبب — ده مصدر الحقيقة
        // الوحيد اللي بيوصل في كل الحالات.
        if (status == 'notListening' || status == 'done') {
          onStopped?.call();
        }
      },
      // بندوّر على محرّك التعرّف بالـintent — من غيرها بعض الأجهزة
      // (خصوصًا اللي من غير خدمات جوجل كاملة) مبتلاقيش المحرّك أصلًا.
      options: [SpeechToText.androidIntentLookup],
    );

    if (_available) _localeId = await _resolveLocale();
    return _available;
  }

  String _describe(String code) => switch (code) {
    'error_network' || 'error_network_timeout' =>
      'التعرّف على الكلام محتاج نت والاتصال ضعيف. اكتب رسالتك أو جرّب ثاني.',
    'error_audio' || 'error_client' => 'صار خلل في المايك. جرّب مرة ثانية.',
    'error_insufficient_permissions' =>
      'إذن المايك مرفوض — فعّله من إعدادات الجهاز.',
    'error_busy' ||
    'error_recognizer_busy' => 'المايك مشغول مع تطبيق ثاني. سكّره وجرّب هنا.',
    _ => 'ما قدرت أسمعك. جرّب مرة ثانية أو اكتب رسالتك.',
  };

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
        // إلغاء عند العطل كان بيرمي الكلام اللي اتلقط قبل العطل — إيقاف
        // عادي بيسيبه مكتوب في الصندوق والمستخدم يكمّل عليه.
        cancelOnError: false,
        // ٥ ثواني سكوت: التلاتة كانت بتقصقص الجملة لما المستخدم ياخد نفس
        // في نص ميعاد طويل («بكرة الساعة… خمسة العصر»).
        pauseFor: const Duration(seconds: 5),
        listenFor: const Duration(seconds: 60),
      ),
    );
  }

  Future<void> stop() => _speech.stop();

  Future<void> cancel() => _speech.cancel();
}
