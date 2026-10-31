import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// لوجو تعاونوا: كفين مفتوحين بيكوّنوا مصحف مفتوح، وفوقهم نقطة ذهبي.
/// مرسوم بنفس مسارات التصميم (مساحة رسم 200×200).
class LogoMark extends StatelessWidget {
  const LogoMark({
    super.key,
    this.size = 96,
    Color? leftColor,
    Color? rightColor,
  })  : _left = leftColor,
        _right = rightColor;

  /// نسخة للخلفيات الغامقة.
  const LogoMark.onDark({super.key, this.size = 96})
      : _left = Colors.white,
        _right = const Color(0xFFBFDBFE);

  final double size;
  final Color? _left;
  final Color? _right;

  // الافتراضي حسب الوضع (فاتح/غامق).
  Color get leftColor => _left ?? (AppColors.isDark ? Colors.white : AppColors.navy);
  Color get rightColor => _right ?? (AppColors.isDark ? const Color(0xFF93C5FD) : AppColors.blue);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'تعاونوا',
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _LogoPainter(leftColor, rightColor),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.left, this.right);

  final Color left;
  final Color right;

  static Path _hand() => Path()
    ..moveTo(100, 84)
    ..cubicTo(80, 70, 50, 64, 28, 72)
    ..quadraticBezierTo(15, 76, 19, 86)
    ..quadraticBezierTo(12, 93, 19, 103)
    ..quadraticBezierTo(12, 110, 20, 120)
    ..quadraticBezierTo(15, 128, 24, 134)
    ..lineTo(32, 148)
    ..cubicTo(54, 140, 80, 142, 100, 154)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200, size.height / 200);

    final hand = _hand();
    canvas.drawPath(hand, Paint()..color = left);

    // انعكاس أفقي حوالين منتصف مساحة الرسم: x' = 200 - x
    final mirror = Float64List.fromList([-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 200, 0, 0, 1]);
    canvas.drawPath(hand.transform(mirror), Paint()..color = right);

    canvas.drawCircle(const Offset(100, 56), 9, Paint()..color = AppColors.gold);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.left != left || old.right != right;
}
