import 'package:flutter/material.dart';

import '../models/storage_centre.dart';
import '../theme/app_theme.dart';

/// Compact centre card. Two layouts:
///
/// * Default (full-width on alerts/trip screens): stacks name → stats → pills
/// * Compact (horizontal scroll on map screen): fixed 220×120 rect with just
///   the essentials — name, distance, ETA.
class CentreCard extends StatelessWidget {
  final StorageCentre centre;
  final VoidCallback? onTap;
  final bool isRecommended;
  final bool compact;

  const CentreCard({
    super.key,
    required this.centre,
    this.onTap,
    this.isRecommended = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return compact ? _buildCompact(context) : _buildFull(context);
  }

  // -------------------------------------------------------------------------
  // Compact (map bottom sheet, horizontally scrollable)
  // -------------------------------------------------------------------------
  Widget _buildCompact(BuildContext context) {
    final theme = Theme.of(context);
    final distance = centre.distanceKm?.toStringAsFixed(1) ?? '—';
    final eta = centre.estimatedMinutes?.toString() ?? '—';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isRecommended
                  ? AppColors.primary.withValues(alpha: 0.6)
                  : AppColors.border,
              width: isRecommended ? 1.5 : 1,
            ),
            boxShadow: isRecommended
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      blurRadius: 14,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isRecommended)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'RECOMMENDED',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.primary,
                      fontSize: 9,
                    ),
                  ),
                ),
              const Spacer(),
              Text(centre.name,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.route,
                      size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text('$distance km',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textPrimary)),
                  const SizedBox(width: 10),
                  const Icon(Icons.timer_outlined,
                      size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text('$eta min',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textPrimary)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Full (trip / alerts screen)
  // -------------------------------------------------------------------------
  Widget _buildFull(BuildContext context) {
    final theme = Theme.of(context);
    final distance = centre.distanceKm?.toStringAsFixed(1) ?? '—';
    final eta = centre.estimatedMinutes?.toString() ?? '—';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isRecommended
                  ? AppColors.primary.withValues(alpha: 0.7)
                  : AppColors.border,
              width: isRecommended ? 1.5 : 1,
            ),
            boxShadow: isRecommended
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      centre.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isRecommended)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'RECOMMENDED',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: AppColors.primary,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Stat(icon: Icons.route, label: '$distance km'),
                  const SizedBox(width: 16),
                  _Stat(icon: Icons.timer_outlined, label: '$eta min'),
                  const SizedBox(width: 16),
                  _Stat(
                    icon: Icons.thermostat,
                    label: '${centre.minTemp.toStringAsFixed(0)}–'
                        '${centre.maxTemp.toStringAsFixed(0)}°C',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _Pill(
                    label: centre.isOpen ? 'OPEN' : 'CLOSED',
                    colour: centre.isOpen ? AppColors.safe : AppColors.danger,
                  ),
                  const SizedBox(width: 8),
                  _Pill(
                    label:
                        centre.hasCapacity ? 'HAS CAPACITY' : 'NO CAPACITY',
                    colour: centre.hasCapacity
                        ? AppColors.safe
                        : AppColors.warning,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Stat({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color colour;

  const _Pill({required this.label, required this.colour});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colour,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
