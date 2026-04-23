import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../config/env.dart';
import '../../models/storage_centre.dart';
import '../../providers/sensor_provider.dart';
import '../../providers/storage_centre_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/constants.dart';
import '../../widgets/centre_card.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  GoogleMapController? _controller;

  @override
  Widget build(BuildContext context) {
    final rider = ref
        .watch(riderPositionProvider)
        .maybeWhen(data: (p) => p, orElse: () => AppConstants.defaultLocation);
    final nearbyAsync = ref.watch(nearbyCentresProvider);
    final risk = ref.watch(riskAssessmentProvider);

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('rider'),
        position: rider,
        icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'You'),
      ),
      ...nearbyAsync.maybeWhen(
        data: (centres) => centres
            .map((c) => Marker(
                  markerId: MarkerId(c.id),
                  position: c.location,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    _hueFor(risk.level, centres.first.id == c.id),
                  ),
                  infoWindow: InfoWindow(
                    title: c.name,
                    snippet:
                        '${c.distanceKm?.toStringAsFixed(1)} km · ${c.estimatedMinutes} min',
                  ),
                ))
            .toSet(),
        orElse: () => const <Marker>{},
      ),
    };

    // Do not instantiate GoogleMap without a real API key — that crashes
    // iOS natively. Fall back to a list-only view with a hint.
    final mapPanel = Env.hasGoogleMapsKey
        ? GoogleMap(
            initialCameraPosition: CameraPosition(target: rider, zoom: 12),
            markers: markers,
            onMapCreated: (c) => _controller = c,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          )
        : const _MapUnavailableNotice();

    return Scaffold(
      appBar: AppBar(title: const Text('Nearest Centres')),
      body: Column(
        children: [
          SizedBox(height: 320, child: mapPanel),
          Expanded(
            child: nearbyAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorState(message: '$e'),
              data: (centres) => centres.isEmpty
                  ? _EmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: centres.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => CentreCard(
                        centre: centres[i],
                        isRecommended: i == 0,
                        onTap: () => _focus(centres[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _focus(StorageCentre c) async {
    await _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(c.location, 14),
    );
  }

  double _hueFor(RiskLevel level, bool isRecommended) {
    if (isRecommended) return BitmapDescriptor.hueGreen;
    return BitmapDescriptor.hueViolet;
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off,
                size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              'No nearby storage centres found within '
              '${AppConstants.storageCentreSearchRadiusKm.toStringAsFixed(0)} km.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: AppColors.danger),
            const SizedBox(height: 12),
            Text(message, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _MapUnavailableNotice extends StatelessWidget {
  const _MapUnavailableNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined,
                size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text('Map unavailable',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Google Maps API key is not configured.\n'
              'See README → "Google Maps API key" to enable.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              'The centre list below still works.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
