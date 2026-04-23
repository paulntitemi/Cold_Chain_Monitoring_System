import 'dart:math' as math;

import '../models/sensor_reading.dart';
import '../theme/app_theme.dart';
import '../utils/constants.dart';

class RiskAssessment {
  final double riskScore;
  final RiskLevel level;
  final int timeOutsideRangeMinutes;
  final int remainingSafeMinutes;
  final bool isOutsideRange;
  final double temperature;

  const RiskAssessment({
    required this.riskScore,
    required this.level,
    required this.timeOutsideRangeMinutes,
    required this.remainingSafeMinutes,
    required this.isOutsideRange,
    required this.temperature,
  });

  static const unknown = RiskAssessment(
    riskScore: 0,
    level: RiskLevel.unknown,
    timeOutsideRangeMinutes: 0,
    remainingSafeMinutes: AppConstants.maxSafeMinutesOutsideRange,
    isOutsideRange: false,
    temperature: double.nan,
  );
}

/// Stateless-ish risk calculator that takes the current reading plus the
/// cumulative seconds spent outside the safe range during this trip, and
/// returns a [RiskAssessment].
class RiskEngine {
  final double safeMin;
  final double safeMax;
  final int maxSafeMinutes;

  const RiskEngine({
    this.safeMin = AppConstants.safeMinTemp,
    this.safeMax = AppConstants.safeMaxTemp,
    this.maxSafeMinutes = AppConstants.maxSafeMinutesOutsideRange,
  });

  RiskAssessment assess({
    required SensorReading reading,
    required int durationOutsideRangeSeconds,
  }) {
    final temp = reading.temperature;
    final outsideRange = temp < safeMin || temp > safeMax;
    final timeOutsideMinutes = durationOutsideRangeSeconds / 60.0;

    final timeFactor = (timeOutsideMinutes / maxSafeMinutes).clamp(0.0, 1.0);

    double deviation;
    if (temp < safeMin) {
      // The lower we go below safe_min, the worse. We use safe_min itself
      // as the denominator so reaching 0 °C yields 1.0.
      deviation = safeMin == 0 ? 1.0 : (safeMin - temp) / safeMin;
    } else if (temp > safeMax) {
      // Scale from safe_max up to 15 °C → 1.0.
      final headroom = math.max(1.0, 15 - safeMax);
      deviation = (temp - safeMax) / headroom;
    } else {
      deviation = 0.0;
    }
    deviation = deviation.clamp(0.0, 1.0);

    final riskScore = (timeFactor * 0.6 + deviation * 0.4).clamp(0.0, 1.0);
    final remaining =
        math.max(0, maxSafeMinutes - timeOutsideMinutes).floor();

    return RiskAssessment(
      riskScore: riskScore,
      level: _level(riskScore),
      timeOutsideRangeMinutes: timeOutsideMinutes.floor(),
      remainingSafeMinutes: remaining,
      isOutsideRange: outsideRange,
      temperature: temp,
    );
  }

  RiskLevel _level(double score) {
    if (score < 0.30) return RiskLevel.low;
    if (score < 0.65) return RiskLevel.medium;
    if (score < 0.85) return RiskLevel.high;
    return RiskLevel.critical;
  }
}
