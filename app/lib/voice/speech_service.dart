import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// سبب تعذّر تشغيل المايك — كل واحد له رسالة وحل مختلف.
enum MicProblem {
  none,

  /// إذن المايك مرفوض أو انتهى («مرة واحدة»). الحل عند المستخدم.
  permission,

  /// الجهاز نفسه مافيهوش محرّك تعرّف على الكلام. مافيش حل — الكتابة بس.
  noEngine;

  String get message => switch (this) {
    MicProblem.none => '',
    MicProblem.permission =>
      'إذن المايك مقفول. افتح إعدادات التطبيق واسمح بالمايك، '
          'واختار «أثناء استخدام التطبيق» مش «مرة واحدة».',
    MicProblem.noEngine =>
      'جهازك ما فيه محرّك تعرّف على الكلام، فالتسجيل الصوتي ما راح يشتغل '
          'عليه. اكتب رسالتك وأنا أفهمها عادي.',
  };
}

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

  /// اللهجات العربية المرشّحة بالترتيب، وأول وحدة يقبلها المحرّك هي اللي
  /// بتشتغل. المحرّك بيرفض اللي مش منزّلة عنده بـerror_language_not_supported،
  /// وقبل كده كان الرفض ده يوقّف المايك خالص — الرسالة العامة «ما قدرت
  /// أسمعك» ما بتقولش إن اللغة هي المشكلة، فالمستخدم يفتكر الزرار باظ.
  List<String> _locales = const [_preferredLocale];
  int _current = 0;

  /// بنبدّل اللهجة دلوقتي — لازم نكتم إشارة «وقف الاستماع» عشان زرار
  /// المايك ما يرجعش لحالته والمحاولة التانية لسه شغالة.
  bool _switchingLocale = false;

  void Function(String text, bool isFinal)? _onResult;

  /// الاستماع وقف — سواء المستخدم سكت، أو المهلة خلصت، أو حصل عطل.
  /// الواجهة لازم تسمع ده عشان زرار المايك ما يفضلش شكله «بيسمع» وهو واقف:
  /// نتيجة نهائية (isFinal) مش مضمونة توصل أصلًا — لو ما فيش كلام اتلقط،
  /// المحرّك بيقفل من غير أي onResult، وده كان بيسيب المايك معلّق للأبد.
  void Function()? onStopped;

  /// عطل بلغة المستخدم — يتعرض له بدل ما يضيع في اللوج.
  void Function(String message)? onProblem;

  bool get isListening => _speech.isListening;

  /// اللغة اللي هيتفرّغ بيها الكلام. بتتعرض في فحص المايك بالإعدادات —
  /// «الصوت بيطلع إنجليزي» كان باج حقيقي، والسطر ده بيكشفه على طول.
  String get localeId => _locales[_current];

  /// هل المحرّك أعلن عن أي لهجة عربية في قايمته؟
  ///
  /// لو لأ، إحنا بنفرض ar_SA على أمل إنه يقبلها — وكتير بيرفضها وقت
  /// **الاستماع** مش وقت التهيئة. يعني `initialize()` بترجّع true والمايك
  /// مش شغّال فعليًا، فزرار الفحص كان هيطمّن المستخدم غلط. السطر ده هو
  /// اللي بيخلّي الفحص يقول الحقيقة.
  bool arabicListed = false;

  /// سبب آخر فشل في تشغيل المايك.
  ///
  /// رسالة واحدة عامة لكل الأسباب كانت بتسيب المستخدم واقف: «فعّل التعرّف
  /// على الكلام» نصيحة مالهاش معنى على جهاز مافيهوش محرّك أصلًا، و«راجع
  /// الإذن» مالهاش معنى والإذن مسموح.
  MicProblem lastProblem = MicProblem.none;

  /// بيرجّع false لو الجهاز مبيدعمش التفريغ أو المستخدم رفض إذن المايك.
  Future<bool> initialize() async {
    // ما بنكاشش النجاح للأبد: إذن «مرة واحدة» بينتهي، والمستخدم ممكن يسحب
    // الإذن من إعدادات الجهاز والتطبيق شغّال. الكاش القديم كان بيخلّي زرار
    // المايك يشتغل شكلًا وبعدين يفشل من غير ما حد يعرف ليه.
    if (_available && await _speech.hasPermission) {
      lastProblem = MicProblem.none;
      return true;
    }

    _available = await _speech.initialize(
      onError: (e) {
        debugPrint('speech error: ${e.errorMsg}');
        // المحرّك رفض اللهجة دي لأنها مش منزّلة عنده. نجرّب اللي بعدها بدل
        // ما المايك يفشل. مافيش رجوع للغة غير عربية عن قصد: صاحب العمل
        // بيتكلم عربي بس، ونص إنجليزي ملخبط أسوأ من رسالة واضحة.
        if (e.errorMsg == 'error_language_not_supported' && _nextLocale()) {
          _retryWithNextLocale();
          return;
        }
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
        if (_switchingLocale) return;
        if (status == 'notListening' || status == 'done') {
          onStopped?.call();
        }
      },
      // بندوّر على محرّك التعرّف بالـintent — من غيرها بعض الأجهزة
      // (خصوصًا اللي من غير خدمات جوجل كاملة) مبتلاقيش المحرّك أصلًا.
      options: [SpeechToText.androidIntentLookup],
    );

    if (_available) {
      lastProblem = MicProblem.none;
      _locales = await _resolveLocales();
      _current = 0;
    } else {
      // الإذن مسموح ورغم كده التهيئة فشلت = مافيش محرّك تعرّف على الجهاز.
      // بيحصل على أجهزة من غير خدمات جوجل كاملة (هواوي، وبعض تشاومي
      // وإنفنكس)، وساعتها مافيش أي حاجة المستخدم يعملها في الإعدادات —
      // يكتب رسالته وخلاص.
      lastProblem = await _speech.hasPermission
          ? MicProblem.noEngine
          : MicProblem.permission;
    }
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
    // وصلنا هنا يعني كل اللهجات العربية اترفضت — العربي مو منزّل للتعرّف
    // على الكلام. الحل عند المستخدم وخطواته واضحة، فنقولها بالنص.
    'error_language_not_supported' =>
      'اللغة العربية مو منزّلة للتعرّف على الكلام في جهازك. نزّلها من: '
          'إعدادات الجهاز ← اللغات والإدخال ← الإدخال الصوتي ← اللغات، '
          'واختار العربية. لين ذاك الوقت اكتب رسالتك وأنا أفهمها عادي.',
    _ => 'ما قدرت أسمعك. جرّب مرة ثانية أو اكتب رسالتك.',
  };

  /// بيرجّع معرّف لغة عربي **دايمًا** — عمره ما بيرجّع «خلّيها للجهاز».
  ///
  /// النسخة القديمة كانت بترجّع null لو قائمة locales() ما فيهاش عربي،
  /// والمحرّك ساعتها بيستخدم لغة الجهاز الافتراضية — وعلى أجهزة كتير دي
  /// إنجليزي، فكلام المستخدم العربي كان بيتفرّغ حروف إنجليزي ملخبطة.
  /// المشكلة إن القائمة نفسها مش موثوقة: محرّكات كتير بترجّعها ناقصة أو
  /// فاضية مع إنها بتفهم العربي عادي لو اتطلب صراحة. فلو ما لقيناش عربي
  /// في القائمة بنفرض ar_SA برضه — أسوأ نتيجة إن المحرّك يرفضها بعطل
  /// واضح للمستخدم، وده أحسن ألف مرة من إنجليزي صامت غلط.
  Future<List<String>> _resolveLocales() async {
    final ordered = <String>[];
    try {
      final ids = (await _speech.locales()).map((l) => l.localeId).toList();
      for (final id in [_preferredLocale, 'ar-SA']) {
        if (ids.contains(id)) ordered.add(id);
      }
      // باقي اللهجات العربية كبدائل مرتّبة — لو السعودي مش منزّل، المصري
      // أو المصفوف تاني يفرّغ الكلام صح برضه.
      ordered.addAll(
        ids.where((id) => id.startsWith('ar_') || id.startsWith('ar-')),
      );
    } on Exception catch (e) {
      debugPrint('تعذّرت قراءة لغات التعرّف: $e');
    }
    arabicListed = ordered.isNotEmpty;
    // القايمة نفسها مش موثوقة: محرّكات كتير بترجّعها ناقصة أو فاضية وهي
    // فاهمة عربي عادي لو اتطلب صراحة، فبنجرّب ar_SA لو مالقيناش أي عربي.
    if (ordered.isEmpty) ordered.add(_preferredLocale);
    return ordered.toSet().toList(growable: false);
  }

  /// ينتقل للّهجة العربية اللي بعدها. false لو خلصوا كلهم.
  bool _nextLocale() {
    if (_current + 1 >= _locales.length) return false;
    _current += 1;
    debugPrint('اللغة اترفضت — بنجرّب ${_locales[_current]}');
    return true;
  }

  Future<void> _retryWithNextLocale() async {
    _switchingLocale = true;
    try {
      // المحرّك لسه بيقفل جلسته؛ نداء listen فورًا بيرجع busy.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await _listen();
    } on Exception catch (e) {
      debugPrint('فشل تبديل اللغة: $e');
      onStopped?.call();
    } finally {
      _switchingLocale = false;
    }
  }

  /// يبدأ الاستماع. [onResult] بتتنده مع كل تحديث — النتيجة النهائية بيبقى
  /// معاها [isFinal] = true.
  Future<void> start({
    required void Function(String text, bool isFinal) onResult,
  }) async {
    if (!await initialize()) return;
    // بيتخزّن عشان إعادة المحاولة بلهجة تانية تقدر تكمّل على نفس الصندوق.
    _onResult = onResult;
    await _listen();
  }

  Future<void> _listen() async {
    final onResult = _onResult;
    if (onResult == null) return;

    await _speech.listen(
      onResult: (result) =>
          onResult(result.recognizedWords, result.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: localeId,
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
