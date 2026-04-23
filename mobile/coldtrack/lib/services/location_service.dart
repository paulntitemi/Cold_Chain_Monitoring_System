import 'dart:async';
import 'dart:developer' as developer;

import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../utils/constants.dart';

enum LocationStatus { available, permissionDenied, disabled, unknown }

class LocationSnapshot {
  final LatLng position;
  final double? accuracyMeters;
  final DateTime capturedAtUtc;

  LocationSnapshot({
    required this.position,
    this.accuracyMeters,
    required this.capturedAtUtc,
  });
}

class LocationService {
  LocationSnapshot? _last;
  LocationStatus _status = LocationStatus.unknown;
  StreamSubscription<Position>? _watch;
  final _controller = StreamController<LocationSnapshot>.broadcast();

  LocationSnapshot? get last => _last;
  LocationStatus get status => _status;
  Stream<LocationSnapshot> get updates => _controller.stream;

  /// Falls back to [AppConstants.defaultLocation] if GPS unavailable, so the
  /// rest of the app (centre scoring) can still run.
  LatLng get currentOrDefault => _last?.position ?? AppConstants.defaultLocation;

  Future<LocationStatus> ensurePermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _status = LocationStatus.disabled;
        return _status;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _status = LocationStatus.permissionDenied;
      } else {
        _status = LocationStatus.available;
      }
    } catch (e) {
      developer.log('Location permission check failed: $e',
          name: 'LocationService');
      _status = LocationStatus.unknown;
    }
    return _status;
  }

  /// Start watching position updates. Safe to call multiple times.
  Future<void> start() async {
    if (_watch != null) return;
    final status = await ensurePermission();
    if (status != LocationStatus.available) return;

    _watch = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // metres
      ),
    ).listen((p) {
      _last = LocationSnapshot(
        position: LatLng(p.latitude, p.longitude),
        accuracyMeters: p.accuracy,
        capturedAtUtc: p.timestamp.toUtc(),
      );
      _controller.add(_last!);
    }, onError: (Object e) {
      developer.log('Position stream error: $e', name: 'LocationService');
    });

    try {
      final first = await Geolocator.getCurrentPosition();
      _last = LocationSnapshot(
        position: LatLng(first.latitude, first.longitude),
        accuracyMeters: first.accuracy,
        capturedAtUtc: first.timestamp.toUtc(),
      );
      _controller.add(_last!);
    } catch (_) {/* ignore — stream will eventually deliver */}
  }

  Future<void> stop() async {
    await _watch?.cancel();
    _watch = null;
    await _controller.close();
  }
}
