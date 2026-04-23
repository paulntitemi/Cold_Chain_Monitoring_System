import 'package:equatable/equatable.dart';

import '../theme/app_theme.dart';
import 'storage_centre.dart';

enum AlertResponse { accepted, ignored, escalated }

class Alert extends Equatable {
  final String id;
  final DateTime timestamp;
  final RiskLevel riskLevel;
  final double temperatureAtTrigger;
  final double riskScore;
  final int remainingSafeMinutes;
  final StorageCentre? recommendedCentre;
  final AlertResponse? response;

  const Alert({
    required this.id,
    required this.timestamp,
    required this.riskLevel,
    required this.temperatureAtTrigger,
    required this.riskScore,
    required this.remainingSafeMinutes,
    this.recommendedCentre,
    this.response,
  });

  Alert copyWith({AlertResponse? response}) => Alert(
        id: id,
        timestamp: timestamp,
        riskLevel: riskLevel,
        temperatureAtTrigger: temperatureAtTrigger,
        riskScore: riskScore,
        remainingSafeMinutes: remainingSafeMinutes,
        recommendedCentre: recommendedCentre,
        response: response ?? this.response,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'riskLevel': riskLevel.name,
        'temperatureAtTrigger': temperatureAtTrigger,
        'riskScore': riskScore,
        'remainingSafeMinutes': remainingSafeMinutes,
        if (recommendedCentre != null)
          'recommendedCentre': recommendedCentre!.toJson(),
        if (response != null) 'response': response!.name,
      };

  @override
  List<Object?> get props => [
        id,
        timestamp,
        riskLevel,
        temperatureAtTrigger,
        riskScore,
        remainingSafeMinutes,
        response,
      ];
}
