import 'package:flutter_test/flutter_test.dart';
import 'package:sekerter/device/contacts_service.dart';
import 'package:sekerter/device/messaging_service.dart';

/// اختبارات أخطر منطق في التطبيق: تحويل الأرقام السعودية لصيغة واتساب،
/// وتوحيد الأسماء العربية عشان «أبو سعد» و«ابو سعد» يطابقوا بعض.
///
/// غلطة هنا معناها إن السكرتير يكلّم الرقم الغلط أو ما يلقى الشخص أصلًا.
void main() {
  group('تحويل الأرقام لصيغة واتساب', () {
    test('رقم سعودي محلي 05 يتحوّل لـ9665', () {
      expect(MessagingService.international('0501234567'), '966501234567');
      expect(MessagingService.international('0559876543'), '966559876543');
    });

    test('رقم بدون صفر بادئ (٩ خانات) يتحوّل برضه', () {
      expect(MessagingService.international('501234567'), '966501234567');
    });

    test('الصيغة الدولية بـ+ تشيل علامة الزائد بس', () {
      expect(MessagingService.international('+966501234567'), '966501234567');
      // رقم مصري لصاحب عمل له تعاملات برّه — ما نفترض السعودية دايمًا.
      expect(MessagingService.international('+201001234567'), '201001234567');
    });

    test('الصيغة الدولية بـ00 تشيل الصفرين', () {
      expect(MessagingService.international('00966501234567'), '966501234567');
    });

    test('المسافات والشُّرَط والأقواس تنشال', () {
      expect(
        MessagingService.international('+966 50 123 4567'),
        '966501234567',
      );
      expect(MessagingService.international('(050) 123-4567'), '966501234567');
    });

    test('رقم دولي بدون بادئة يُترك زي ما هو', () {
      // ٨ خانات تبدأ بـ5 — مو رقم جوال سعودي، ما نحطش 966 من عندنا.
      expect(MessagingService.international('51234567'), '51234567');
    });

    test('clean يشيل الفواصل بس ويسيب + والأرقام', () {
      expect(MessagingService.clean('+966 50-123 (4567)'), '+966501234567');
    });
  });

  group('تمييز الرقم من الاسم', () {
    test('الأرقام بأشكالها تتعرف كأرقام', () {
      expect(ContactsService.looksLikeNumber('0501234567'), isTrue);
      expect(ContactsService.looksLikeNumber('+966 50 123 4567'), isTrue);
      expect(ContactsService.looksLikeNumber('(050) 123-4567'), isTrue);
    });

    test('الأسماء ما تتعرفش كأرقام', () {
      expect(ContactsService.looksLikeNumber('أبو سعد'), isFalse);
      expect(ContactsService.looksLikeNumber('الدكتور خالد'), isFalse);
      // قصير جدًا ما ينفع يكون رقم جوال.
      expect(ContactsService.looksLikeNumber('12345'), isFalse);
    });
  });

  group('توحيد الأسماء العربية', () {
    test('أشكال الألف كلها تتوحّد', () {
      final expected = ContactsService.fold('ابو سعد');
      for (final variant in ['أبو سعد', 'إبو سعد', 'آبو سعد']) {
        expect(ContactsService.fold(variant), expected, reason: variant);
      }
    });

    test('الياء والألف المقصورة تتوحّد', () {
      expect(ContactsService.fold('مصطفى'), ContactsService.fold('مصطفي'));
    });

    test('التاء المربوطة والهاء تتوحّد', () {
      expect(ContactsService.fold('حمزة'), ContactsService.fold('حمزه'));
    });

    test('التشكيل ينشال', () {
      expect(ContactsService.fold('مُحَمَّد'), ContactsService.fold('محمد'));
    });

    test('المسافات الزايدة تتوحّد', () {
      expect(ContactsService.fold('  أبو    سعد  '), 'ابو سعد');
    });

    test('أسماء مختلفة تفضل مختلفة', () {
      // التوحيد ما ينفعش يخلّي أسماء مختلفة تطابق بعض.
      expect(
        ContactsService.fold('أبو سعد'),
        isNot(ContactsService.fold('أبو سعود')),
      );
      expect(ContactsService.fold('خالد'), isNot(ContactsService.fold('خلود')));
    });

    test('normalise يشيل الفواصل من الرقم', () {
      expect(ContactsService.normalise('050 123-4567'), '0501234567');
    });
  });

  group('فتح واتساب: السكيم المباشر الأول وwa.me احتياطي', () {
    // كانت canLaunchUrl هي الحكم، وهي معروف إنها بتكذب على أندرويد ١١+
    // فكانت بترجّع «واتساب مو منصّب» والواتساب منصّب. دلوقتي بنجرّب الفتح
    // فعلًا: whatsapp:// الأول (بيفتح التطبيق نفسه)، وبعده wa.me.

    test('واتساب موجود → السكيم المباشر يكفي ومحاولة واحدة', () async {
      final attempts = <Uri>[];
      final service = MessagingService(
        openExternal: (uri) async {
          attempts.add(uri);
          return uri.scheme == 'whatsapp';
        },
      );

      final outcome = await service.whatsapp('0501234567', 'تأخرت شوي');

      expect(outcome, SendOutcome.opened);
      expect(attempts, hasLength(1));
      expect(attempts.single.scheme, 'whatsapp');
      expect(attempts.single.queryParameters['phone'], '966501234567');
      expect(attempts.single.queryParameters['text'], 'تأخرت شوي');
    });

    test('السكيم المباشر فشل → wa.me يتجرّب قبل ما نستسلم', () async {
      final attempts = <Uri>[];
      final service = MessagingService(
        openExternal: (uri) async {
          attempts.add(uri);
          return uri.host == 'wa.me';
        },
      );

      final outcome = await service.whatsapp('0501234567', 'وصلت');

      expect(outcome, SendOutcome.opened);
      expect(attempts, hasLength(2));
      expect(attempts.first.scheme, 'whatsapp');
      expect(
        attempts.last.toString(),
        startsWith('https://wa.me/966501234567'),
      );
    });

    test('الاتنين فشلوا → «واتساب مو منصّب» مش صمت', () async {
      final service = MessagingService(openExternal: (_) async => false);
      expect(
        await service.whatsapp('0501234567', 'اهلا'),
        SendOutcome.appMissing,
      );
    });

    test('الرسالة النصية بتفتح تطبيق الرسايل والنص جاهز', () async {
      final attempts = <Uri>[];
      final service = MessagingService(
        openExternal: (uri) async {
          attempts.add(uri);
          return true;
        },
      );

      final outcome = await service.sms('0501234567', 'وصلت');

      expect(outcome, SendOutcome.opened);
      expect(attempts.single.scheme, 'sms');
      expect(attempts.single.queryParameters['body'], 'وصلت');
    });
  });
}
