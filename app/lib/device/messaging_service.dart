import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:url_launcher/url_launcher.dart';

/// الاتصال وإرسال الرسايل.
///
/// حدود المنصّتين هنا حقيقية ومش قابلة للالتفاف:
///
///   • **الاتصال** — أندرويد يقدر يطلب الرقم مباشرة بإذن CALL_PHONE. آيفون
///     يفتح شاشة الاتصال والمستخدم يضغط، وما فيه طريقة غيرها.
///
///   • **واتساب** — ما فيه أي منصّة تسمح بإرسال صامت من تطبيق تاني. أقصى
///     المتاح على الجهازين إننا نفتح واتساب والرسالة مكتوبة جاهزة، وصاحب
///     العمل يضغط إرسال. أي حل «إرسال تلقائي كامل» معناه أتمتة واتساب ويب
///     أو عميل غير رسمي — مخالف لشروطهم وعقوبته حظر الرقم، وده رقم شغله.
///
///   • **رسالة نصية** — نفس الشي: نفتح تطبيق الرسايل والنص جاهز.
enum SendOutcome {
  /// انفتح التطبيق والرسالة جاهزة — ناقص ضغطة إرسال واحدة.
  opened,

  /// التطبيق مو منصّب على الجهاز.
  appMissing,

  failed,
}

class MessagingService {
  /// يطلب رقم. على أندرويد مباشرة لو الإذن متاح، وإلا يفتح شاشة الاتصال.
  Future<bool> call(String phone) async {
    final number = _clean(phone);

    if (Platform.isAndroid) {
      try {
        await AndroidIntent(
          action: 'android.intent.action.CALL',
          data: 'tel:$number',
        ).launch();
        return true;
      } on Exception {
        // الإذن مرفوض أو مافي تطبيق اتصال — نرجع لشاشة الطلب.
      }
    }

    return _open(Uri(scheme: 'tel', path: number));
  }

  /// يفتح واتساب والرسالة مكتوبة. الإرسال بضغطة من صاحب العمل.
  Future<SendOutcome> whatsapp(String phone, String text) async {
    final number = _international(phone);

    // wa.me هو الرابط الرسمي وبيشتغل على الجهازين.
    final uri = Uri.parse(
      'https://wa.me/$number?text=${Uri.encodeComponent(text)}',
    );

    if (await canLaunchUrl(uri)) {
      return await _open(uri) ? SendOutcome.opened : SendOutcome.failed;
    }
    return SendOutcome.appMissing;
  }

  /// يفتح تطبيق الرسايل والنص جاهز.
  Future<SendOutcome> sms(String phone, String text) async {
    final number = _clean(phone);
    // آيفون يبي & وأندرويد يقبل ?body= — Uri بيبنيها صح للاتنين.
    final uri = Uri(
      scheme: 'sms',
      path: number,
      queryParameters: {'body': text},
    );
    return await _open(uri) ? SendOutcome.opened : SendOutcome.failed;
  }

  Future<bool> _open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception {
      return false;
    }
  }

  static String _clean(String phone) =>
      phone.replaceAll(RegExp(r'[\s\-()]'), '');

  /// واتساب يبي الرقم بصيغة دولية بدون + ولا أصفار بادئة.
  ///
  /// الأرقام السعودية اللي تبدأ بـ05 تتحوّل لـ9665، وده الشكل اللي دفتر
  /// التليفون عادة يخزّنها فيه محليًا.
  static String _international(String phone) {
    var number = _clean(phone);
    if (number.startsWith('+')) return number.substring(1);
    if (number.startsWith('00')) return number.substring(2);
    if (number.startsWith('05')) return '966${number.substring(1)}';
    if (number.startsWith('5') && number.length == 9) return '966$number';
    return number;
  }
}
