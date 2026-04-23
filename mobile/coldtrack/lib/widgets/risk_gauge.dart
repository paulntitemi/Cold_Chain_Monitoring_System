import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Circular 270° arc gauge, Cyberla-style.
///
/// * Smoothly tweens between progress values using TweenAnimationBuilder.
/// * Breathes with a pulse — slow when safe, fast + glowy when critical.
/// * Stroke width: 12px. Arc sweep: 270° (−135° → +135°).
class RiskGauge extends StatefulWidget {
  final double score;
  final RiskLevel level;
  final double size;

  const RiskGauge({
    super.key,
    required this.score,
    required this.level,
    this.size = 260,
  });

  @override
  State<RiskGauge> createState() => _RiskGaugeState();
}

class _RiskGaugeState extends State<RiskGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: widget.level.pulseDuration,
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant RiskGauge old) {
    super.didUpdateWidget(old);
    if (old.level != widget.level) {
      _pulse
        ..duration = widget.level.pulseDuration
        ..reset()
        ..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = widget.level.color;

    return SizedBox(
      width: widget.size,
      height: widget.size * 0.82, // 270° sweep reclaims the bottom 1/4
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Animated sweep + pulse glow
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) {
              return TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                tween: Tween(begin: 0, end: widget.score.clamp(0.0, 1.0)),
                builder: (_, progress, __) {
                  return CustomPaint(
                    size: Size(widget.size, widget.size),
                    painter: _RiskGaugePainter(
                      progress: progress,
                      colour: colour,
                      pulse: _pulse.value,
                      level: widget.level,
                    ),
                  );
                },
              );
            },
          ),

          // Centre numeral + label
          Padding(
            padding: EdgeInsets.only(bottom: widget.size * 0.04),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  tween: Tween(begin: 0, end: widget.score.clamp(0.0, 1.0)),
                  builder: (_, v, __) {
                    return Text(
                      (v * 100).toStringAsFixed(0),
                      style: theme.textTheme.displayLarge?.copyWith(
                        color: colour,
                        fontSize: 72,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  widget.level.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colour,
                    letterSpacing: 2.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text('SPOILAGE RISK',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      letterSpacing: 1.5,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskGaugePainter extends CustomPainter {
  final double progress;
  final Color colour;
  final double pulse; // 0..1 (triangle wave)
  final RiskLevel level;

  _RiskGaugePainter({
    required this.progress,
    required this.colour,
    required this.pulse,
    required this.level,
  });

  static const _start = -math.pi * 3 / 4; // −135°
  static const _sweep = math.pi * 3 / 2; // 270°
  static const _strokeWidth = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - (_strokeWidth / 2) - 6;

    // Track
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = AppColors.border;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      _start,
      _sweep,
      false,
      track,
    );

    // Outer glow — stronger + larger when risk is higher, pulsing with _pulse.
    final glowAlpha = _glowAlphaForLevel(level, pulse);
    if (glowAlpha > 0) {
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth + 12 * pulse
        ..strokeCap = StrokeCap.round
        ..color = colour.withValues(alpha: glowAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        _start,
        _sweep * progress,
        false,
        glow,
      );
    }

    // Main sweep — gradient along the arc, never transparent at the leading
    // end so the numeral is anchored visually.
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: _start,
        endAngle: _start + _sweep,
        colors: [colour.withValues(alpha: 0.45), colour],
      ).createShader(Rect.fromCircle(center: centre, radius: radius));
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      _start,
      _sweep * progress,
      false,
      fill,
    );

    // Tick marks (10 minor + 3 major at 0 / 50 / 100)
    final tickPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    const majorTickPaintColour = AppColors.textSecondary;
    for (var i = 0; i <= 10; i++) {
      final t = i / 10.0;
      final angle = _start + _sweep * t;
      final isMajor = i == 0 || i == 5 || i == 10;
      final inner = centre +
          Offset(math.cos(angle), math.sin(angle)) *
              (radius - _strokeWidth / 2 - (isMajor ? 8 : 4));
      final outer = centre +
          Offset(math.cos(angle), math.sin(angle)) *
              (radius - _strokeWidth / 2 - 1);
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = isMajor ? majorTickPaintColour : tickPaint.color
          ..strokeWidth = isMajor ? 1.5 : 1,
      );
    }
  }

  double _glowAlphaForLevel(RiskLevel l, double p) {
    switch (l) {
      case RiskLevel.low:
        return 0.08 * p;
      case RiskLevel.medium:
        return 0.18 * p;
      case RiskLevel.high:
        return 0.32 * p;
      case RiskLevel.critical:
        return 0.55 * p;
      case RiskLevel.unknown:
        return 0.0;
    }
  }

  @override
  bool shouldRepaint(covariant _RiskGaugePainter old) =>
      old.progress != progress ||
      old.colour != colour ||
      old.pulse != pulse ||
      old.level != level;
}
