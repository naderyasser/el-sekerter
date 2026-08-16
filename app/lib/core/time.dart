import 'package:flutter/foundation.dart';

/// وقت الجهاز بصيغة ISO 8601 **ومعاه فرق التوقيت**.
///
/// `DateTime.toIso8601String()` على وقت محلي بيرمي فرق التوقيت خالص:
/// بيطلّع `2026-08-16T23:40:00.000` من غير أي إشارة للمنطقة. السيرفر
/// بيبعت النص ده للموديل كـ«الوقت الحالي»، والموديل مطلوب منه يرجّع وقت
/// الموعد بفرق توقيت — فبيخمّنه.
///
/// التخمين ده بيعدّي معظم الوقت وبيتكسر في أسوأ لحظة: الساعة ١١:٤٠ بالليل
/// في الرياض، لو الموديل فهم الوقت على إنه UTC يبقى عنده لسه ٨:٤٠ مساءً —
/// و«بكرة» تطلع النهاردة. الموعد يتسجّل في يوم فات والتذكير ما يرنّش أبدًا.
///
/// السطر ده يشيل التخمين من المعادلة.
String isoWithOffset(DateTime at) {
  final local = at.toLocal();
  final offset = local.timeZoneOffset;

  final sign = offset.isNegative ? '-' : '+';
  final absolute = offset.abs();
  final hours = absolute.inHours.toString().padLeft(2, '0');
  final minutes = (absolute.inMinutes % 60).toString().padLeft(2, '0');

  // بدون الملّي ثانية — ما لهاش أي معنى في سياق المواعيد.
  final stamp = local.toIso8601String().split('.').first;

  return '$stamp$sign$hours:$minutes';
}

@visibleForTesting
String nowIso() => isoWithOffset(DateTime.now());
