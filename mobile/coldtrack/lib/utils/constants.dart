import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/storage_centre.dart';

class AppConstants {
  // ---------------------------------------------------------------------
  // Risk engine thresholds
  // ---------------------------------------------------------------------
  static const double safeMinTemp = 2.0;
  static const double safeMaxTemp = 8.0;
  static const int maxSafeMinutesOutsideRange = 30;

  // ---------------------------------------------------------------------
  // Polling / staleness
  // ---------------------------------------------------------------------
  static const Duration pollInterval = Duration(seconds: 5);
  static const Duration staleReadingThreshold = Duration(seconds: 15);
  static const Duration apiRetryBackoff = Duration(seconds: 5);
  static const int apiMaxRetries = 3;

  // ---------------------------------------------------------------------
  // Alert re-triggering
  // ---------------------------------------------------------------------
  static const Duration criticalAlertRetriggerAfter = Duration(minutes: 2);

  // ---------------------------------------------------------------------
  // History buffer
  // ---------------------------------------------------------------------
  static const int readingsRingBufferSize = 50;

  // ---------------------------------------------------------------------
  // Credential refresh
  // ---------------------------------------------------------------------
  static const Duration credentialRefreshLeeway = Duration(minutes: 5);

  // ---------------------------------------------------------------------
  // Location defaults (Accra, Ghana)
  // ---------------------------------------------------------------------
  static const LatLng defaultLocation = LatLng(5.6037, -0.1870);
  static const double storageCentreSearchRadiusKm = 20.0;
  static const double riderSpeedKmPerMinute = 0.5; // ~30 km/h urban

  // ---------------------------------------------------------------------
  // Fallback storage centres (used when API endpoint is not yet deployed).
  // TODO: remove once GET /storage-centres is live in production.
  // ---------------------------------------------------------------------
  static final List<StorageCentre> fallbackStorageCentres = [
    StorageCentre(
      id: 'korle-bu',
      name: 'Korle Bu Cold Store',
      location: const LatLng(5.5322, -0.2275),
      minTemp: 2.0,
      maxTemp: 8.0,
      hasCapacity: true,
      isOpen: true,
    ),
    StorageCentre(
      id: 'ridge',
      name: 'Ridge Hospital Pharmacy',
      location: const LatLng(5.5641, -0.1969),
      minTemp: 2.0,
      maxTemp: 8.0,
      hasCapacity: true,
      isOpen: true,
    ),
    StorageCentre(
      id: '37-military',
      name: '37 Military Hospital',
      location: const LatLng(5.6090, -0.1720),
      minTemp: 2.0,
      maxTemp: 8.0,
      hasCapacity: false,
      isOpen: true,
    ),
    StorageCentre(
      id: 'legon',
      name: 'Legon Medical Centre',
      location: const LatLng(5.6488, -0.1866),
      minTemp: 2.0,
      maxTemp: 8.0,
      hasCapacity: true,
      isOpen: true,
    ),
    StorageCentre(
      id: 'tema',
      name: 'Tema Cold Chain Hub',
      location: const LatLng(5.6698, -0.0166),
      minTemp: 2.0,
      maxTemp: 8.0,
      hasCapacity: true,
      isOpen: true,
    ),
  ];
}
