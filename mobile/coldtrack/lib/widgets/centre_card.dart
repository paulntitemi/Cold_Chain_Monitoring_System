import 'package:flutter/material.dart';

import '../models/storage_centre.dart';
import '../theme/app_theme.dart';

class CentreCard extends StatelessWidget {
  final StorageCentre centre;
  final VoidCallback? onTap;
  final bool isRecommended;

  const CentreCard({
    super.key,
    required this.centre,
    this.onTap,
    this.isRecommended = false,
  });

  @override
  Widget build(BuildContext context) {
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
                      spreadRadius: 0,
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
