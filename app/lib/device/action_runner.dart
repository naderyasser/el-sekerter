import '../models/server_action.dart';
import 'contacts_service.dart';
import 'messaging_service.dart';

/// نتيجة تنفيذ أمر جهاز، بشكل رسالة تتعرض في الشات.
class ActionOutcome {
  const ActionOutcome(this.message, {this.needsChoice = false});

  final String message;

  /// السكرتير محتاج صاحب العمل يوضّح مين يقصد.
  final bool needsChoice;
}

/// ينفّذ أوامر الاتصال والرسايل.
///
/// المطابقة مع دفتر التليفون كلها هنا محليًا — السيرفر بيرجّع اسم زي ما صاحب
/// العمل نطقه، وما بيشوف ولا رقم ولا جهة اتصال.
///
/// لو الاسم طابق أكثر من واحد، ما نخمّنش: نرجّع سؤال يتعرض في الشات. تكليم
/// الشخص الغلط أسوأ بكثير من سؤال زيادة.
class DeviceActionRunner {
  DeviceActionRunner(this._contacts, this._messaging);

  final ContactsService _contacts;
  final MessagingService _messaging;

  Future<ActionOutcome?> run(ServerAction action) async {
    return switch (action.type) {
      ActionType.call => _call(action),
      ActionType.message => _message(action),
      // باقي الأنواع مواعيد، وبينفّذها AppointmentStore.
      _ => null,
    };
  }

  Future<ActionOutcome> _call(ServerAction action) async {
    final resolved = await _resolve(action.who!);
    if (resolved is! ContactMatch) return resolved as ActionOutcome;

    final ok = await _messaging.call(resolved.phone);
    return ActionOutcome(
      ok ? 'أطلب ${resolved.name}…' : 'ما قدرت أفتح الاتصال.',
    );
  }

  Future<ActionOutcome> _message(ServerAction action) async {
    final resolved = await _resolve(action.who!);
    if (resolved is! ContactMatch) return resolved as ActionOutcome;

    // الرسايل المجدولة بتتحوّل لموعد وبتتنفّذ في وقتها، مش هنا.
    final isWhatsapp = action.channel != 'sms';
    final outcome = isWhatsapp
        ? await _messaging.whatsapp(resolved.phone, action.text!)
        : await _messaging.sms(resolved.phone, action.text!);

    return ActionOutcome(switch (outcome) {
      // ما فيه إرسال صامت على أي منصّة — الضغطة الأخيرة لازم تكون منه.
      SendOutcome.opened =>
        'فتحت ${isWhatsapp ? 'واتساب' : 'الرسايل'} لـ${resolved.name} '
            'والرسالة جاهزة — اضغط إرسال.',
      SendOutcome.appMissing => 'واتساب مو منصّب على جوالك.',
      SendOutcome.failed => 'ما قدرت أفتح التطبيق.',
    });
  }

  /// يرجّع [ContactMatch] لو المطابقة واضحة، أو [ActionOutcome] فيه سؤال.
  Future<Object> _resolve(String who) async {
    final matches = await _contacts.search(who);

    if (matches.isEmpty) {
      return ActionOutcome(
        'ما لقيت «$who» في جهات اتصالك. ابعت لي رقمه.',
        needsChoice: true,
      );
    }

    if (matches.length > 1) {
      final names = matches.take(4).map((m) => m.name).join('، ');
      return ActionOutcome(
        'عندك أكثر من «$who»: $names. أي واحد فيهم؟',
        needsChoice: true,
      );
    }

    return matches.single;
  }
}
