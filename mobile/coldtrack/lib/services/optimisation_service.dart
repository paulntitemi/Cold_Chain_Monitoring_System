import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/shipment.dart';
import '../models/storage_centre.dart';
import '../utils/constants.dart';
import 'api_service.dart';

/// Ranks nearby cold storage centres when risk is rising.
///
/// Pipeline:
///   1. Fetch centres via [ApiService] (falls back to hardcoded list).
///   2. Filter: open, has capacity, can hold the shipment's temperature range.
///   3. Compute haversine distance from rider's current position.
///   4. Estimate travel time assuming [AppConstants.riderSpeedKmPerMinute].
///   5. Score = distance_km * 0.7 + travel_time_minutes * 0.3.
///   6. Return the top 3 viable centres sorted by ascending score.
class OptimisationService {
  final ApiService api;
  OptimisationService(this.api);

  Future<List<StorageCentre>> rankNearbyCentres({
    required LatLng riderPosition,
    required Shipment shipment,
    int topN = 3,
  }) async {
    final raw = await api.getStorageCentres(
      lat: riderPosition.latitude,
      lng: riderPosition.longitude,
    );

    final viable = raw.where((c) =>
        c.isOpen &&
        c.hasCapacity &&
        c.minTemp <= shipment.minSafeTemp &&
        c.maxTemp >= shipment.maxSafeTemp);

    final scored = viable.map((c) {
      final distanceKm = _haversineKm(riderPosition, c.location);
      final travelMinutes =
          (distanceKm / AppConstants.riderSpeedKmPerMinute).round();
      final score = distanceKm * 0.7 + travelMinutes * 0.3;
      return c.copyWith(
        distanceKm: distanceKm,
        estimatedMinutes: travelMinutes,
        score: score,
      );
    }).toList()
      ..sort((a, b) => (a.score ?? 0).compareTo(b.score ?? 0));

    return scored.take(topN).toList();
  }

  /// Haversine distance in kilometres between two LatLng points.
  static double _haversineKm(LatLng a, LatLng b) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLng = _toRad(b.longitude - a.longitude);

    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_toRad(a.latitude)) *
            math.cos(_toRad(b.latitude)) *
            math.pow(math.sin(dLng / 2), 2);

    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return earthRadiusKm * c;
  }

  static double _toRad(double deg) => deg * math.pi / 180.0;
}
