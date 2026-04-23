import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Rounded-rect stat pill: small tracked label above, bold value below.
/// Used in horizontal rows on the trip screen.
class StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColour;
  final IconData? icon;

  const StatPill({
    super.key,
    required this.label,
    required this.value,
    this.valueColour,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedValueColour = valueColour ?? AppColors.textPrimary;

    // Fixed internal dimensions so three pills in a Row are always the
    // same height, regardless of whether the value is "5.2°" or "00:00".
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 11, color: AppColors.primary),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          // FittedBox + single-line constraint guarantees the value
          // always fits on one row, scaling down where necessary.
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.displaySmall?.copyWith(
                  color: resolvedValueColour,
                  fontSize: 24,
                  height: 1.0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
