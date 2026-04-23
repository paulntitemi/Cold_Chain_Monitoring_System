import 'package:equatable/equatable.dart';

class Shipment extends Equatable {
  final String id;
  final String deviceId;
  final String riderId;
  final String riderName;
  final String vaccineType;
  final String destination;
  final DateTime startTime;
  final double minSafeTemp;
  final double maxSafeTemp;

  const Shipment({
    required this.id,
    required this.deviceId,
    required this.riderId,
    required this.riderName,
    required this.vaccineType,
    required this.destination,
    required this.startTime,
    this.minSafeTemp = 2.0,
    this.maxSafeTemp = 8.0,
  });

  factory Shipment.fromJson(Map<String, dynamic> json) => Shipment(
        id: json['id'] as String,
        deviceId: json['deviceId'] as String,
        riderId: json['riderId'] as String,
        riderName: json['riderName'] as String,
        vaccineType: json['vaccineType'] as String,
        destination: json['destination'] as String,
        startTime: DateTime.parse(json['startTime'] as String),
        minSafeTemp: (json['minSafeTemp'] as num?)?.toDouble() ?? 2.0,
        maxSafeTemp: (json['maxSafeTemp'] as num?)?.toDouble() ?? 8.0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'deviceId': deviceId,
        'riderId': riderId,
        'riderName': riderName,
        'vaccineType': vaccineType,
        'destination': destination,
        'startTime': startTime.toUtc().toIso8601String(),
        'minSafeTemp': minSafeTemp,
        'maxSafeTemp': maxSafeTemp,
      };

  @override
  List<Object?> get props => [
        id,
        deviceId,
        riderId,
        riderName,
        vaccineType,
        destination,
        startTime,
        minSafeTemp,
        maxSafeTemp,
      ];
}
