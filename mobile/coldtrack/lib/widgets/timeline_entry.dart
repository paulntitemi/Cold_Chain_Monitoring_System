import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Single entry in a dot-and-line vertical timeline.
///
/// * [dotColor] paints the marker — risk colour for alerts, monochrome for logs.
/// * [iconOnDot] overlays an icon inside the marker (log-screen variant).
/// * [dashedLine] = true draws the connecting line as a dash pattern to indicate
///   "no response yet"; false draws a solid line.
/// * [isLast] hides the trailing connector (last item in the list).
class TimelineEntry extends StatelessWidget {
  final Widget child;
  final Color dotColor;
  final IconData? iconOnDot;
  final bool dashedLine;
  final bool isLast;
  final double dotSize;

  const TimelineEntry({
    super.key,
    required this.child,
    required this.dotColor,
    this.iconOnDot,
    this.dashedLine = false,
    this.isLast = false,
    this.dotSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left column: dot + connector line
          SizedBox(
            width: 36,
            child: CustomPaint(
              painter: _TimelinePainter(
                dotColor: dotColor,
                dashed: dashedLine,
                isLast: isLast,
                dotSize: dotSize,
              ),
              child: iconOnDot == null
                  ? const SizedBox.expand()
                  : Padding(
                      padding: EdgeInsets.only(top: dotSize / 2 + 1),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Icon(
                          iconOnDot,
                          size: dotSize * 0.6,
                          color: AppColors.background,
                        ),
                      ),
                    ),
            ),
          ),
          // Right column: content card
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: 4,
                bottom: isLast ? 0 : 16,
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final Color dotColor;
  final bool dashed;
  final bool isLast;
  final double dotSize;

  _TimelinePainter({
    required this.dotColor,
    required this.dashed,
    required this.isLast,
    required this.dotSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final dotCentreY = dotSize / 2 + 4;

    // Connector line below the dot
    if (!isLast) {
      final startY = dotCentreY + dotSize / 2 + 2;
      final endY = size.height;
      final paint = Paint()
        ..color = dotColor.withValues(alpha: 0.5)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;

      if (dashed) {
        const dashLength = 5.0;
        const gap = 4.0;
        double y = startY;
        while (y < endY) {
          canvas.drawLine(Offset(cx, y),
              Offset(cx, (y + dashLength).clamp(0, endY)), paint);
          y += dashLength + gap;
        }
      } else {
        canvas.drawLine(Offset(cx, startY), Offset(cx, endY), paint);
      }
    }

    // Dot — filled with a border ring
    final fill = Paint()..color = dotColor;
    final ring = Paint()
      ..color = dotColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawCircle(Offset(cx, dotCentreY), dotSize / 2 + 3, ring);
    canvas.drawCircle(Offset(cx, dotCentreY), dotSize / 2, fill);
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      old.dotColor != dotColor ||
      old.dashed != dashed ||
      old.isLast != isLast ||
      old.dotSize != dotSize;
}
