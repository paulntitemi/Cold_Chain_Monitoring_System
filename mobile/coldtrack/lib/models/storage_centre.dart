import 'package:google_maps_flutter/google_maps_flutter.dart';

class StorageCentre {
  final String id;
  final String name;
  final LatLng location;
  final double minTemp;
  final double maxTemp;
  final bool hasCapacity;
  final bool isOpen;

  // Populated by OptimisationService; never persisted.
  double? distanceKm;
  int? estimatedMinutes;
  double? score;

  StorageCentre({
    required this.id,
    required this.name,
    required this.location,
    required this.minTemp,
    required this.maxTemp,
    required this.hasCapacity,
    required this.isOpen,
    this.distanceKm,
    this.estimatedMinutes,
    this.score,
  });

  factory StorageCentre.fromJson(Map<String, dynamic> json) => StorageCentre(
        id: json['id'] as String,
        name: json['name'] as String,
        location: LatLng(
          (json['lat'] as num).toDouble(),
          (json['lng'] as num).toDouble(),
        ),
        minTemp: (json['minTemp'] as num?)?.toDouble() ?? 2.0,
        maxTemp: (json['maxTemp'] as num?)?.toDouble() ?? 8.0,
        hasCapacity: json['hasCapacity'] as bool? ?? true,
        isOpen: json['isOpen'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': location.latitude,
        'lng': location.longitude,
        'minTemp': minTemp,
        'maxTemp': maxTemp,
        'hasCapacity': hasCapacity,
        'isOpen': isOpen,
      };

  StorageCentre copyWith({
    double? distanceKm,
    int? estimatedMinutes,
    double? score,
  }) {
    return StorageCentre(
      id: id,
      name: name,
      location: location,
      minTemp: minTemp,
      maxTemp: maxTemp,
      hasCapacity: hasCapacity,
      isOpen: isOpen,
      distanceKm: distanceKm ?? this.distanceKm,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      score: score ?? this.score,
    );
  }
}
