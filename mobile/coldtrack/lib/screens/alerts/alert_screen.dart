import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/alert.dart';
import '../../providers/alert_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/extensions.dart';
import '../../widgets/status_badge.dart';

class AlertScreen extends ConsumerWidget {
  const AlertScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: alerts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined,
                      size: 56, color: AppColors.safe),
                  const SizedBox(height: 12),
                  Text('No alerts', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Temperature is within safe range.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: alerts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _AlertCard(
                alert: alerts[i],
                onRespond: (resp) => ref
                    .read(alertControllerProvider.notifier)
                    .respondTo(alerts[i].id, resp),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colour.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: colour.withValues(alpha: 0.15),
            blurRadius: 18,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusBadge(level: alert.riskLevel),
              const Spacer(),
              Text(alert.timestamp.toLocal().relativeToNow,
                  style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${alert.temperatureAtTrigger.toStringAsFixed(2)} °C',
            style: theme.textTheme.displayMedium?.copyWith(color: colour),
          ),
          const SizedBox(height: 4),
          Text(
            'Risk ${(alert.riskScore * 100).toStringAsFixed(0)}% · '
            '${alert.remainingSafeMinutes}m safe window',
            style: theme.textTheme.bodyMedium,
          ),
          if (alert.recommendedCentre != null) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Text('NEAREST VIABLE CENTRE',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(alert.recommendedCentre!.name,
                style: theme.textTheme.titleMedium),
            Text(
              '${alert.recommendedCentre!.distanceKm?.toStringAsFixed(1)} km · '
              '${alert.recommendedCentre!.estimatedMinutes} min',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          if (alert.response == null)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onRespond(AlertResponse.ignored),
                    child: const Text('IGNORE'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onRespond(AlertResponse.escalated),
                    child: const Text('ESCALATE'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => onRespond(AlertResponse.accepted),
                    child: const Text('DIVERT NOW'),
                  ),
                ),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _responseColour(alert.response!).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 16, color: _responseColour(alert.response!)),
                  const SizedBox(width: 8),
                  Text(
                    'Rider response: ${alert.response!.name.toUpperCase()}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _responseColour(alert.response!),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _responseColour(AlertResponse r) {
    switch (r) {
      case AlertResponse.accepted:
        return AppColors.safe;
      case AlertResponse.escalated:
        return AppColors.warning;
      case AlertResponse.ignored:
        return AppColors.danger;
    }
  }
}
