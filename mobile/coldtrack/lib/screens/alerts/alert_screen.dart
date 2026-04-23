import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/alert.dart';
import '../../providers/alert_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/extensions.dart';
import '../../widgets/timeline_entry.dart';

class AlertScreen extends ConsumerWidget {
  const AlertScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertControllerProvider);
    final theme = Theme.of(context);

    if (alerts.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Alerts')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined, size: 56, color: AppColors.safe),
              const SizedBox(height: 12),
              Text('No alerts', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Temperature is within safe range.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '${alerts.length} TOTAL',
                style: theme.textTheme.labelLarge,
              ),
            ),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: alerts.length,
        itemBuilder: (_, i) => TimelineEntry(
          dotColor: alerts[i].riskLevel.color,
          dashedLine: alerts[i].response == null,
          isLast: i == alerts.length - 1,
          child: _AlertCard(
            alert: alerts[i],
            onRespond: (resp) => ref
                .read(alertControllerProvider.notifier)
                .respondTo(alerts[i].id, resp),
          ),
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final Alert alert;
  final void Function(AlertResponse) onRespond;

  const _AlertCard({required this.alert, required this.onRespond});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = alert.riskLevel.color;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colour.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: colour.withValues(alpha: 0.1),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                alert.riskLevel.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colour,
                  letterSpacing: 1.8,
                ),
              ),
              const Spacer(),
              Text(alert.timestamp.toLocal().relativeToNow,
                  style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                alert.temperatureAtTrigger.toStringAsFixed(1),
                style: theme.textTheme.displayMedium?.copyWith(color: colour),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 2),
                child: Text('°C', style: theme.textTheme.titleMedium),
              ),
              const SizedBox(width: 14),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${(alert.riskScore * 100).toStringAsFixed(0)}% RISK',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: AppColors.textSecondary,
                        )),
                    Text('${alert.remainingSafeMinutes}m left',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          if (alert.recommendedCentre != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_pharmacy,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      alert.recommendedCentre!.name,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${alert.recommendedCentre!.distanceKm?.toStringAsFixed(1)} km',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (alert.response == null)
            Row(
              children: [
                Expanded(
                  child: _ResponseButton(
                    label: 'IGNORE',
                    colour: AppColors.textSecondary,
                    onTap: () => onRespond(AlertResponse.ignored),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ResponseButton(
                    label: 'ESCALATE',
                    colour: AppColors.warning,
                    onTap: () => onRespond(AlertResponse.escalated),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _ResponseButton(
                    label: 'DIVERT',
                    colour: AppColors.primary,
                    filled: true,
                    onTap: () => onRespond(AlertResponse.accepted),
                  ),
                ),
              ],
            )
          else
            _ResponsePillBadge(response: alert.response!),
        ],
      ),
    );
  }
}

class _ResponseButton extends StatelessWidget {
  final String label;
  final Color colour;
  final bool filled;
  final VoidCallback onTap;

  const _ResponseButton({
    required this.label,
    required this.colour,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? colour : Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colour),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: filled ? AppColors.background : colour,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _ResponsePillBadge extends StatelessWidget {
  final AlertResponse response;
  const _ResponsePillBadge({required this.response});

  (String, Color) get _meta {
    switch (response) {
      case AlertResponse.accepted:
        return ('ACCEPTED', AppColors.primary);
      case AlertResponse.ignored:
        return ('IGNORED', AppColors.warning);
      case AlertResponse.escalated:
        return ('ESCALATED', AppColors.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (label, colour) = _meta;
    return Row(
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colour.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: colour, size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: colour,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
