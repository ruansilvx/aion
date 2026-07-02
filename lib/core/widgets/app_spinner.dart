import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:aion/core/theme/theme_scope.dart';

class AppSpinner extends StatefulWidget {
  const AppSpinner({super.key, this.size = 20.0});

  final double size;

  @override
  State<AppSpinner> createState() => _AppSpinnerState();
}

class _AppSpinnerState extends State<AppSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    return Semantics(
      label: 'Loading',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _SpinnerPainter(
                progress: _controller.value,
                color: t.colors.primary,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final rect = Offset.zero & size;
    final startAngle = -math.pi / 2 + progress * 2 * math.pi;
    const sweepAngle = 270 * math.pi / 180;

    canvas.drawArc(rect.deflate(paint.strokeWidth / 2), startAngle, sweepAngle, false, paint);
  }

  @override
  bool shouldRepaint(covariant _SpinnerPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
