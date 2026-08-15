import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

/// مطابقة الأسماء مع دفتر التليفون.
///
/// **جهات الاتصال عمرها ما تطلع من الجهاز.** الموديل يقول الاسم زي ما صاحب
/// العمل نطقه («أبو سعد»)، والمطابقة كلها تصير هنا محليًا. السيرفر ما يشوف
/// ولا اسم ولا رقم.
class ContactMatch {
  const ContactMatch({required this.name, required this.phone});

  final String name;
  final String phone;
}

class ContactsService {
  bool _granted = false;

  Future<bool> ensurePermission() async {
    if (_granted) return true;
    final status = await FlutterContacts.permissions.request(
      PermissionType.read,
    );
    _granted = status == PermissionStatus.granted;
    return _granted;
  }

  /// يرجّع كل المطابقات مرتّبة من الأقوى للأضعف.
  ///
  /// أكثر من نتيجة معناها إن التطبيق لازم يسأل صاحب العمل مين يقصد بدل ما
  /// يخمّن ويكلّم الشخص الغلط.
  Future<List<ContactMatch>> search(String query) async {
    final cleaned = query.trim();
    if (cleaned.isEmpty) return const [];

    // رقم مكتوب صريح ما يحتاج دفتر تليفون ولا إذن.
    if (looksLikeNumber(cleaned)) {
      return [ContactMatch(name: cleaned, phone: normalise(cleaned))];
    }

    if (!await ensurePermission()) return const [];

    // الاسم والتليفون بس — بدون صور ولا عناوين، أسرع بكثير وما نحتاجها.
    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.name, ContactProperty.phone},
    );

    final needle = fold(cleaned);
    final exact = <ContactMatch>[];
    final partial = <ContactMatch>[];

    for (final contact in contacts) {
      if (contact.phones.isEmpty) continue;
      // displayName اختياري في النموذج — جهة اتصال بلا اسم ما تنفعنا.
      final displayName = contact.displayName ?? '';
      final number = contact.phones.first.number;
      if (displayName.isEmpty || number.isEmpty) continue;

      final name = fold(displayName);
      if (name.isEmpty) continue;

      final match = ContactMatch(name: displayName, phone: normalise(number));

      if (name == needle) {
        exact.add(match);
      } else if (name.contains(needle) || needle.contains(name)) {
        partial.add(match);
      }
    }

    return [...exact, ...partial];
  }

  @visibleForTesting
  static bool looksLikeNumber(String value) =>
      RegExp(r'^\+?[\d\s\-()]{7,}$').hasMatch(value);

  @visibleForTesting
  static String normalise(String phone) =>
      phone.replaceAll(RegExp(r'[\s\-()]'), '');

  /// يوحّد الاسم للمقارنة: يشيل التشكيل ويوحّد الألف والياء والتاء المربوطة،
  /// عشان «أبو سعد» و«ابو سعد» يطابقوا بعض.
  @visibleForTesting
  static String fold(String value) {
    var folded = value.trim().toLowerCase();
    folded = folded.replaceAll(RegExp('[ً-ْـ]'), '');
    folded = folded
        .replaceAll(RegExp('[أإآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه');
    return folded.replaceAll(RegExp(r'\s+'), ' ');
  }
}
