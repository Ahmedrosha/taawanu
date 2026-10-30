import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../theme/app_colors.dart';
import 'prayer_controller.dart';
import 'prayer_times.dart';

/// بوصلة القبلة: الدايرة بتلف مع الموبايل، والسهم بيشاور على الكعبة.
class QiblaScreen extends StatelessWidget {
  const QiblaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = PrayerController.instance;
    final qibla = qiblaBearing(c.lat, c.lng);
    final km = distanceToKaabaKm(c.lat, c.lng).round();
    final events = FlutterCompass.events;
    return Scaffold(
      appBar: AppBar(title: Text(t.qiblaDirection, style: const TextStyle(fontWeight: FontWeight.w700))),
      body: events == null
          ? _Message(text: t.noCompass(qibla.round()))
          : StreamBuilder<CompassEvent>(
              stream: events,
              builder: (context, snap) {
                final heading = snap.data?.heading;
                if (snap.hasError || (snap.hasData && heading == null)) {
                  return _Message(text: t.noCompass(qibla.round()));
                }
                if (heading == null) return const Center(child: CircularProgressIndicator());
                // الفرق بين اتجاه الموبايل واتجاه القبلة (من -180 لـ180).
                final diff = ((qibla - heading + 540) % 360) - 180;
                final aligned = diff.abs() <= 4;
                final accuracy = snap.data?.accuracy;
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(
                        aligned ? t.facingQibla : (diff > 0 ? t.turnRight : t.turnLeft),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: aligned ? AppColors.statusDone : AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(t.qiblaBearing(qibla.round()), style: const TextStyle(color: AppColors.textMuted)),
                      const Spacer(),
                      AspectRatio(
                        aspectRatio: 1,
                        child: Transform.rotate(
                          // الدايرة بتلف عكس اتجاه الموبايل، فالشمال يفضل شمال.
                          angle: -heading * math.pi / 180,
                          child: CustomPaint(painter: _DialPainter(qibla: qibla, aligned: aligned)),
                        ),
                      ),
                      const Spacer(),
                      Text(t.distanceToMakkah(km), style: const TextStyle(color: AppColors.textMuted)),
                      if (accuracy != null && accuracy > 30) ...[
                        const SizedBox(height: 10),
                        Text(t.calibrateCompass, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.statusLate)),
                      ],
                      const SizedBox(height: 10),
                      Text(t.qiblaTip, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        ),
      );
}

class _DialPainter extends CustomPainter {
  _DialPainter({required this.qibla, required this.aligned});

  final double qibla;
  final bool aligned;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 8;
    canvas.drawCircle(c, r, Paint()..color = AppColors.surface);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = aligned ? AppColors.statusDone : AppColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = aligned ? 4 : 2,
    );

    // علامات كل ٣٠ درجة، وحرف N للشمال.
    final tick = Paint()
      ..color = AppColors.textMuted
      ..strokeWidth = 2;
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final p1 = c + Offset(math.sin(a), -math.cos(a)) * (r - 4);
      final p2 = c + Offset(math.sin(a), -math.cos(a)) * (r - (i % 3 == 0 ? 18 : 10));
      canvas.drawLine(p1, p2, tick);
    }
    final tp = TextPainter(
      text: const TextSpan(text: 'N', style: TextStyle(color: AppColors.statusLate, fontWeight: FontWeight.w700, fontSize: 18)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c + Offset(-tp.width / 2, -r + 22));

    // سهم القبلة.
    final a = qibla * math.pi / 180;
    final dir = Offset(math.sin(a), -math.cos(a));
    final arrow = Paint()
      ..color = aligned ? AppColors.statusDone : AppColors.navy
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c, c + dir * (r - 40), arrow);
    // الكعبة في طرف السهم.
    final k = c + dir * (r - 40);
    canvas.drawRect(Rect.fromCenter(center: k, width: 26, height: 26), Paint()..color = const Color(0xFF111827));
    canvas.drawRect(Rect.fromLTWH(k.dx - 13, k.dy - 6, 26, 4), Paint()..color = AppColors.gold);
    canvas.drawCircle(c, 7, Paint()..color = AppColors.navy);
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.qibla != qibla || old.aligned != aligned;
}
