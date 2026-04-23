import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Circular gauge showing the current risk score (0.0 – 1.0) with a coloured
/// arc and the risk level label in the centre.
class RiskGauge extends StatelessWidget {
  final double score;
  final RiskLevel level;
  final double size;

  const RiskGauge({
    super.key,
    required this.score,
    required this.level,
    this.size = 220,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = level.color;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RiskGaugePainter(
              progress: score.clamp(0.0, 1.0),
              colour: colour,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(score * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: theme.textTheme.displayMedium?.copyWith(color: colour),
              ),
              const SizedBox(height: 4),
              Text(
                level.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colour,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Spoilage risk',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RiskGaugePainter extends CustomPainter {
  final double progress;
  final Color colour;

  _RiskGaugePainter({required this.progress, required this.colour});

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 14;
    const start = -math.pi * 3 / 4;
    const sweep = math.pi * 3 / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..color = AppColors.border;

    canvas.drawArc(Rect.fromCircle(center: centre, radius: radius),
        start, sweep, false, track);

    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [colour.withValues(alpha: 0.6), colour],
        startAngle: start,
        endAngle: start + sweep,
      ).createShader(Rect.fromCircle(center: centre, radius: radius));

    canvas.drawArc(Rect.fromCircle(center: centre, radius: radius),
        start, sweep * progress, false, fill);
  }

  @override
  bool shouldRepaint(covariant _RiskGaugePainter old) =>
      old.progress != progress || old.colour != colour;
}
