import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/shipment.dart';
import '../models/storage_centre.dart';
import '../services/location_service.dart';
import '../services/optimisation_service.dart';
import '../utils/constants.dart';
import 'sensor_provider.dart';
import 'shipment_provider.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  final service = LocationService();
  service.start(); // fire-and-forget; permission prompt handled inside.
  ref.onDispose(service.stop);
  return service;
});

/// Emits a fresh position whenever GPS reports movement beyond the distance
/// filter. First value is the default location until GPS warms up.
final riderPositionProvider = StreamProvider<LatLng>((ref) async* {
  final service = ref.watch(locationServiceProvider);
  yield service.currentOrDefault;
  await for (final snap in service.updates) {
    yield snap.position;
  }
});

final optimisationServiceProvider = Provider<OptimisationService>((ref) {
  final api = ref.watch(apiServiceProvider);
  return OptimisationService(api);
});

/// Top-3 storage centres ranked by distance + travel time from the rider's
/// current position, filtered for capacity and temperature compatibility.
final nearbyCentresProvider = FutureProvider<List<StorageCentre>>((ref) async {
  final optimiser = ref.watch(optimisationServiceProvider);
  final position = ref
      .watch(riderPositionProvider)
      .maybeWhen(data: (p) => p, orElse: () => AppConstants.defaultLocation);

  final shipment = ref.watch(shipmentProvider) ??
      Shipment(
        id: 'placeholder',
        deviceId: 'placeholder',
        riderId: 'placeholder',
        riderName: 'Rider',
        vaccineType: 'RSV',
        destination: 'Destination',
        startTime: DateTime.now().toUtc(),
      );

  return optimiser.rankNearbyCentres(
    riderPosition: position,
    shipment: shipment,
  );
});
