import 'package:coldtrack/services/risk_engine.dart';
import 'package:coldtrack/models/sensor_reading.dart';
import 'package:coldtrack/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RiskEngine', () {
    const engine = RiskEngine();

    SensorReading read(double t) => SensorReading(
          deviceId: 'test',
          timestamp: DateTime.now().toUtc(),
          temperature: t,
        );

    test('safe temperature with no excursion → LOW', () {
      final a = engine.assess(
          reading: read(5.0), durationOutsideRangeSeconds: 0);
      expect(a.level, RiskLevel.low);
      expect(a.riskScore, 0.0);
    });

    test('above safe max and 15 minutes excursion → MEDIUM or worse', () {
      final a = engine.assess(
          reading: read(10.0), durationOutsideRangeSeconds: 15 * 60);
      expect(a.level.index >= RiskLevel.medium.index, true);
    });

    test('hot and long excursion → CRITICAL', () {
      final a = engine.assess(
          reading: read(14.0), durationOutsideRangeSeconds: 40 * 60);
      expect(a.level, RiskLevel.critical);
    });

    test('below freezing → deviation contributes', () {
      final a = engine.assess(
          reading: read(-2.0), durationOutsideRangeSeconds: 0);
      expect(a.riskScore > 0, true);
    });

    test('remaining safe minutes decreases with excursion time', () {
      final a = engine.assess(
          reading: read(10.0), durationOutsideRangeSeconds: 10 * 60);
      expect(a.remainingSafeMinutes < 30, true);
    });
  });
}
