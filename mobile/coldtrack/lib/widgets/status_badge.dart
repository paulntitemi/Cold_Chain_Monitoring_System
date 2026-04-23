import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Pulsing status badge — a coloured dot + uppercase label.
class StatusBadge extends StatefulWidget {
  final RiskLevel level;
  final String? overrideLabel;
  final bool pulse;

  const StatusBadge({
    super.key,
    required this.level,
    this.overrideLabel,
    this.pulse = true,
  });

  @override
  State<StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<StatusBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = widget.level.color;
    final label = widget.overrideLabel ?? widget.level.label;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colour.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(
                  colour.withValues(alpha: 0.4),
                  colour,
                  widget.pulse ? _ctrl.value : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colour.withValues(
                      alpha: widget.pulse ? 0.5 * _ctrl.value : 0.5,
                    ),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colour,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
