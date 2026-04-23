import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../config/env.dart';
import '../models/shipment.dart';

/// Active shipment for the current rider / trip. Persisted in memory only
/// for Phase 1; Phase 2 will back this with Hive for app-kill survival.
class ShipmentController extends StateNotifier<Shipment?> {
  ShipmentController() : super(null);

  void startTrip({
    required String deviceId,
    required String riderName,
    required String vaccineType,
    required String destination,
    double minSafeTemp = 2.0,
    double maxSafeTemp = 8.0,
  }) {
    state = Shipment(
      id: const Uuid().v4(),
      deviceId: deviceId,
      riderId: const Uuid().v4(),
      riderName: riderName,
      vaccineType: vaccineType,
      destination: destination,
      startTime: DateTime.now().toUtc(),
      minSafeTemp: minSafeTemp,
      maxSafeTemp: maxSafeTemp,
    );
  }

  void endTrip() => state = null;
}

final shipmentProvider =
    StateNotifierProvider<ShipmentController, Shipment?>((ref) {
  return ShipmentController();
});

/// Convenience: the active device ID, falling back to Env default when no
/// trip is running (used on onboarding screens).
final activeDeviceIdProvider = Provider<String>((ref) {
  final shipment = ref.watch(shipmentProvider);
  return shipment?.deviceId ?? Env.defaultDeviceId;
});
