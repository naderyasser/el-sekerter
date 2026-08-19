import 'dart:math' as math;

import 'package:flutter/material.dart';

/// علامة السكرتير: فقاعة كلام على شكل ساعة — نفس رسمة أيقونة التطبيق،
/// مرسومة بالكود عشان تبقى حادة في أي مقاس من غير ملف صورة.
class SecretaryAvatar extends StatelessWidget {
  const SecretaryAvatar({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(painter: _MarkPainter()),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  // ألوان العلامة ثابتة زي الأيقونة — مش من الثيم، عشان الهوية ما تتغيرش
  // بين الفاتح والغامق.
  static const _top = Color(0xFF1F8A68);
  static const _bottom = Color(0xFF0D4635);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(s / 2, s / 2);

    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_top, _bottom],
      ).createShader(Offset.zero & size);
    canvas.drawCircle(center, s / 2, bg);

    // جسم الفقاعة الأبيض: دايرة + ذيل لتحت ناحية المتكلم
    final cx = 0.5 * s;
    final cy = 0.475 * s;
    final r = 0.27 * s;
    final white = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx, cy), r, white);

    Offset onCircle(double deg, [double k = 1]) {
      final t = deg * math.pi / 180;
      return Offset(cx + k * r * math.cos(t), cy + k * r * math.sin(t));
    }

    final tail = Path()
      ..moveTo(onCircle(30).dx, onCircle(30).dy)
      ..lineTo(onCircle(55, 1.48).dx, onCircle(55, 1.48).dy)
      ..lineTo(onCircle(80).dx, onCircle(80).dy)
      ..close();
    canvas.drawPath(tail, white);

    // علامات الساعات الأربع والعقارب على 10:10
    final ink = Paint()
      ..color = _bottom
      ..strokeCap = StrokeCap.round;

    for (final deg in [270.0, 0.0, 90.0, 180.0]) {
      canvas.drawCircle(onCircle(deg, 0.78), 0.027 * s, ink);
    }

    Offset hand(double clockDeg, double len) {
      final t = (clockDeg - 90) * math.pi / 180;
      return Offset(cx + len * s * math.cos(t), cy + len * s * math.sin(t));
    }

    ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.048 * s;
    canvas.drawLine(Offset(cx, cy), hand(300, 0.135), ink);
    ink.strokeWidth = 0.042 * s;
    canvas.drawLine(Offset(cx, cy), hand(60, 0.185), ink);

    ink.style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 0.04 * s, ink);
    canvas.drawCircle(Offset(cx, cy), 0.016 * s, white);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) => false;
}
