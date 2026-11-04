import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../services/prefs.dart';
import '../theme/app_colors.dart';

/// خطوة في الجولة التعريفية: العنصر اللي بيتنوّر، والكلام اللي جنبه.
class TourStep {
  const TourStep(this.target, this.text, {this.padding = 6, this.radius = 14});

  final GlobalKey target;
  final String text;
  final double padding;
  final double radius;
}

/// الجولة التعريفية: الشاشة بتغمق، والعنصر بيفضل منوّر، وجنبه فقاعة فيها "التالي" و"تخطي".
/// كل جولة ليها [id] وبتظهر مرة واحدة بس (لحد ما تتعاد من حسابي).
class Tour {
  Tour._();

  static bool _showing = false;

  /// بيستنى الشاشة تخلص تحميل، وبعدين يعرض الجولة لو لسه متشافتش.
  /// الخطوات اللي عنصرها مش ظاهر (مثلًا زرار للأدمن بس) بتتشال لوحدها.
  static void schedule(BuildContext context, String id, List<TourStep> Function() steps,
      {Duration delay = const Duration(milliseconds: 900)}) {
    if (Prefs.instance.tourDone(id)) return;
    Future.delayed(delay, () {
      if (!context.mounted) return;
      unawaited(show(context, id, steps()));
    });
  }

  static Future<void> show(BuildContext context, String id, List<TourStep> steps) async {
    if (_showing || Prefs.instance.tourDone(id)) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    // التبويبات المخفية بتفضل متبنية: منعرضش جولة لشاشة مش قدام المستخدم.
    if (context.findAncestorWidgetOfExactType<Offstage>()?.offstage ?? false) return;
    final visible = steps.where((s) => s.target.currentContext != null).toList();
    if (visible.isEmpty) return;
    _showing = true;
    try {
      await Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, __, ___) => _TourOverlay(steps: visible),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ));
      await Prefs.instance.setTourDone(id);
    } finally {
      _showing = false;
    }
  }
}

class _TourOverlay extends StatefulWidget {
  const _TourOverlay({required this.steps});

  final List<TourStep> steps;

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> {
  int _i = 0;
  Rect? _rect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  Future<void> _locate() async {
    final ctx = widget.steps[_i].target.currentContext;
    if (ctx == null) return _next();
    // لو العنصر برا الشاشة، ننزل له.
    await Scrollable.ensureVisible(ctx, alignment: 0.3, duration: const Duration(milliseconds: 250));
    if (!mounted || !ctx.mounted) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return _next();
    final p = widget.steps[_i].padding;
    setState(() => _rect = (box.localToGlobal(Offset.zero) & box.size).inflate(p));
  }

  void _next() {
    if (!mounted) return;
    if (_i >= widget.steps.length - 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _i++;
      _rect = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final step = widget.steps[_i];
    final rect = _rect;
    final last = _i == widget.steps.length - 1;

    // الفقاعة تحت العنصر لو فيه مكان، وإلا فوقه.
    const bubbleMax = 220.0;
    final below = rect == null || size.height - rect.bottom - pad.bottom > bubbleMax || rect.top < bubbleMax;
    final bubble = Material(
      color: AppColors.surface,
      elevation: 6,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(step.text, style: TextStyle(fontSize: 15, height: 1.55, color: AppColors.text)),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(t.tourStepOf(_i + 1, widget.steps.length), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                const Spacer(),
                if (!last) TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.tourSkip)),
                FilledButton(onPressed: _next, child: Text(last ? t.tourDone : t.tourNext)),
              ],
            ),
          ],
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _next,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _HolePainter(rect, step.radius))),
          if (rect != null)
            Positioned.fromRect(
              rect: rect,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(step.radius),
                    border: Border.all(color: const Color(0xFFFBBF24), width: 2.5),
                  ),
                ),
              ),
            ),
          if (rect != null)
            Positioned(
              left: 16,
              right: 16,
              top: below ? (rect.bottom + 12).clamp(pad.top + 8, size.height - bubbleMax) : null,
              bottom: below ? null : (size.height - rect.top + 12).clamp(pad.bottom + 8, size.height - pad.top - 60),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: GestureDetector(onTap: () {}, child: bubble),
              ),
            ),
        ],
      ),
    );
  }
}

class _HolePainter extends CustomPainter {
  _HolePainter(this.rect, this.radius);

  final Rect? rect;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = const Color(0xC0000000);
    final all = Path()..addRect(Offset.zero & size);
    final r = rect;
    if (r == null) {
      canvas.drawPath(all, dim);
      return;
    }
    final hole = Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)));
    canvas.drawPath(Path.combine(PathOperation.difference, all, hole), dim);
  }

  @override
  bool shouldRepaint(_HolePainter old) => old.rect != rect || old.radius != radius;
}
