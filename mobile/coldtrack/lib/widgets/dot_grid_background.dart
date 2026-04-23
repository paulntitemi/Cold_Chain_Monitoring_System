import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Subtle dot-grid texture painted at rgba(255,255,255,0.03).
/// Wraps its child — pass `fill: true` to stretch.
class DotGridBackground extends StatelessWidget {
  final Widget child;
  final double spacing;
  final double dotRadius;
  final Color? baseColor;

  const DotGridBackground({
    super.key,
    required this.child,
    this.spacing = 22,
    this.dotRadius = 1,
    this.baseColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: baseColor ?? AppColors.background,
      child: CustomPaint(
        painter: _DotGridPainter(spacing: spacing, radius: dotRadius),
        child: child,
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  final double spacing;
  final double radius;

  _DotGridPainter({required this.spacing, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.gridDot;
    for (double y = spacing / 2; y < size.height; y += spacing) {
      for (double x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter old) =>
      old.spacing != spacing || old.radius != radius;
}
