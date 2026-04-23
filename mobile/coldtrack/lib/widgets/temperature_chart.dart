import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/sensor_reading.dart';
import '../theme/app_theme.dart';
import '../utils/constants.dart';

class TemperatureChart extends StatelessWidget {
  final List<SensorReading> readings;

  const TemperatureChart({super.key, required this.readings});

  @override
  Widget build(BuildContext context) {
    if (readings.length < 2) {
      return Center(
        child: Text(
          'Collecting readings…',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final spots = <FlSpot>[];
    for (var i = 0; i < readings.length; i++) {
      spots.add(FlSpot(i.toDouble(), readings[i].temperature));
    }

    final temps = readings.map((r) => r.temperature);
    final minTemp = (temps.reduce((a, b) => a < b ? a : b)) - 1;
    final maxTemp = (temps.reduce((a, b) => a > b ? a : b)) + 1;
    final displayMin = minTemp.clamp(-5.0, AppConstants.safeMinTemp - 1);
    final displayMax = maxTemp.clamp(AppConstants.safeMaxTemp + 1, 20.0);

    return LineChart(
      LineChartData(
        minY: displayMin,
        maxY: displayMax,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 2,
          getDrawingHorizontalLine: (v) => const FlLine(
            color: AppColors.border,
            strokeWidth: 0.5,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: 2,
              getTitlesWidget: (v, _) => Text(
                v.toStringAsFixed(0),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: AppConstants.safeMinTemp,
              color: AppColors.safe.withValues(alpha: 0.6),
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
            HorizontalLine(
              y: AppConstants.safeMaxTemp,
              color: AppColors.safe.withValues(alpha: 0.6),
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: AppColors.primary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withValues(alpha: 0.3),
                  AppColors.primary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touches) {
              return touches.map((t) {
                final idx = t.x.toInt().clamp(0, readings.length - 1);
                final r = readings[idx];
                return LineTooltipItem(
                  '${r.temperature.toStringAsFixed(2)} °C\n'
                  '${r.timestamp.toLocal().hour.toString().padLeft(2, '0')}:'
                  '${r.timestamp.toLocal().minute.toString().padLeft(2, '0')}:'
                  '${r.timestamp.toLocal().second.toString().padLeft(2, '0')}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}
