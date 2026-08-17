import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:android_intent_plus/android_intent.dart';
import 'package:permission_handler/permission_handler.dart';
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
  /// [openExternal] قابلة للحقن عشان الاختبارات تتحقق من ترتيب المحاولات
  /// من غير ما تفتح تطبيقات بجد.
  MessagingService({Future<bool> Function(Uri uri)? openExternal})
    : _openExternal = openExternal ?? _launch;

  final Future<bool> Function(Uri uri) _openExternal;

  static Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception {
      // مافيش تطبيق يفتح الرابط ده — بنرجّع false والمنادي يجرّب البديل.
      return false;
    }
  }

  /// يطلب رقم. على أندرويد مباشرة لو الإذن متاح، وإلا يفتح شاشة الاتصال.
  Future<bool> call(String phone) async {
    final number = clean(phone);

    if (Platform.isAndroid) {
      // CALL_PHONE إذن وقت تشغيل — إعلانه في المانيفست ما يكفيش. قبل
      // التصليح ده محدش كان بيطلبه أبدًا، فـ ACTION_CALL كان بيرمي
      // SecurityException من أول مرة وعلى طول. أول طلب بيطلّع حوار
      // النظام؛ لو رفض، بنفتح شاشة الاتصال والرقم مكتوب وهو يضغط.
      try {
        final granted = await Permission.phone.request();
        if (granted.isGranted) {
          await AndroidIntent(
            action: 'android.intent.action.CALL',
            data: 'tel:$number',
          ).launch();
          return true;
        }
      } on Exception {
        // الإذن اترفض أو مافي تطبيق اتصال — نرجع لشاشة الطلب.
      }
    }

    return _openExternal(Uri(scheme: 'tel', path: number));
  }

  /// يفتح واتساب والرسالة مكتوبة. الإرسال بضغطة من صاحب العمل.
  ///
  /// الترتيب مقصود: سكيم `whatsapp://` الأول لأنه يفتح التطبيق نفسه
  /// مباشرة. `wa.me` احتياطي بس — رابط https ممكن أندرويد يوجهه للمتصفح
  /// بدل واتساب. والنسخة القديمة كانت تسأل canLaunchUrl الأول، وده معروف
  /// إنه بيرجّع false غلط على أندرويد ١١+ — فكانت تستسلم من غير ما تجرّب.
  /// دلوقتي بنجرّب فعلًا ونشوف النتيجة.
  Future<SendOutcome> whatsapp(String phone, String text) async {
    final number = international(phone);
    final encoded = Uri.encodeComponent(text);

    final direct = Uri.parse('whatsapp://send?phone=$number&text=$encoded');
    if (await _openExternal(direct)) return SendOutcome.opened;

    final web = Uri.parse('https://wa.me/$number?text=$encoded');
    if (await _openExternal(web)) return SendOutcome.opened;

    return SendOutcome.appMissing;
  }

  /// يفتح تطبيق الرسايل والنص جاهز.
  Future<SendOutcome> sms(String phone, String text) async {
    final number = clean(phone);
    // آيفون يبي & وأندرويد يقبل ?body= — Uri بيبنيها صح للاتنين.
    final uri = Uri(
      scheme: 'sms',
      path: number,
      queryParameters: {'body': text},
    );
    return await _openExternal(uri) ? SendOutcome.opened : SendOutcome.failed;
  }

  @visibleForTesting
  static String clean(String phone) =>
      phone.replaceAll(RegExp(r'[\s\-()]'), '');

  /// واتساب يبي الرقم بصيغة دولية بدون + ولا أصفار بادئة.
  ///
  /// الأرقام السعودية اللي تبدأ بـ05 تتحوّل لـ9665، وده الشكل اللي دفتر
  /// التليفون عادة يخزّنها فيه محليًا.
  @visibleForTesting
  static String international(String phone) {
    var number = clean(phone);
    if (number.startsWith('+')) return number.substring(1);
    if (number.startsWith('00')) return number.substring(2);
    if (number.startsWith('05')) return '966${number.substring(1)}';
    if (number.startsWith('5') && number.length == 9) return '966$number';
    return number;
  }
}
