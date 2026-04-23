import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../config/env.dart';
import '../../models/storage_centre.dart';
import '../../providers/sensor_provider.dart';
import '../../providers/storage_centre_provider.dart';
import '../../services/risk_engine.dart';
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
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'You'),
      ),
      ...nearbyAsync.maybeWhen(
        data: (centres) => centres
            .map((c) => Marker(
                  markerId: MarkerId(c.id),
                  position: c.location,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    centres.first.id == c.id
                        ? BitmapDescriptor.hueGreen
                        : BitmapDescriptor.hueViolet,
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

    final mapPanel = Env.hasGoogleMapsKey
        ? GoogleMap(
            initialCameraPosition: CameraPosition(target: rider, zoom: 12),
            markers: markers,
            onMapCreated: (c) => _controller = c,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
          )
        : const _MapUnavailableNotice();

    // Full-bleed — no AppBar. 60/40 split driven by screen height.
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Map fills the background
          Positioned.fill(child: mapPanel),

          // Back/status bar strip
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _RoundIconButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  _RoundIconButton(
                    icon: Icons.my_location,
                    onTap: () => _controller
                        ?.animateCamera(CameraUpdate.newLatLngZoom(rider, 14)),
                  ),
                ],
              ),
            ),
          ),

          // Bottom sheet — 40% of screen
          _MapBottomSheet(
            risk: risk,
            nearbyAsync: nearbyAsync,
            onFocus: _focus,
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
}

// ---------------------------------------------------------------------------
// Map bottom sheet — drag handle, safety window strip, horizontal scroll
// ---------------------------------------------------------------------------
class _MapBottomSheet extends StatelessWidget {
  final RiskAssessment risk;
  final AsyncValue<List<StorageCentre>> nearbyAsync;
  final Future<void> Function(StorageCentre) onFocus;

  const _MapBottomSheet({
    required this.risk,
    required this.nearbyAsync,
    required this.onFocus,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.40,
      minChildSize: 0.25,
      maxChildSize: 0.82,
      builder: (_, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 20,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              // Drag handle + safety window strip
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SafetyWindowStrip(risk: risk),
                    const SizedBox(height: 14),
                  ],
                ),
              ),

              // Heading
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        'NEAREST COLD STORAGE',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const Spacer(),
                      if (nearbyAsync.valueOrNull != null)
                        Text(
                          '${nearbyAsync.value!.length}',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 10)),

              // Horizontally-scrollable centre row
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 120,
                  child: nearbyAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Routing unavailable: $e',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    data: (centres) {
                      if (centres.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No centres within '
                            '${AppConstants.storageCentreSearchRadiusKm.toStringAsFixed(0)} km.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        );
                      }
                      return ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: centres.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => CentreCard(
                          centre: centres[i],
                          isRecommended: i == 0,
                          compact: true,
                          onTap: () => onFocus(centres[i]),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // Full details list (appears when sheet is dragged up)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: Text('ALL OPTIONS',
                      style: Theme.of(context).textTheme.labelLarge),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 10)),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: nearbyAsync.when(
                  loading: () => const SliverToBoxAdapter(
                      child: SizedBox.shrink()),
                  error: (_, __) =>
                      const SliverToBoxAdapter(child: SizedBox.shrink()),
                  data: (centres) => SliverList.separated(
                    itemCount: centres.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => CentreCard(
                      centre: centres[i],
                      isRecommended: i == 0,
                      onTap: () => onFocus(centres[i]),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Safety window — horizontal bar showing remaining safe time.
// ---------------------------------------------------------------------------
class _SafetyWindowStrip extends StatelessWidget {
  final RiskAssessment risk;

  const _SafetyWindowStrip({required this.risk});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = AppConstants.maxSafeMinutesOutsideRange;
    final remaining = risk.remainingSafeMinutes.clamp(0, total);
    final progress = remaining / total;
    final colour = risk.level.color;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              Text('SAFETY WINDOW',
                  style: theme.textTheme.labelLarge),
              const Spacer(),
              Text(
                '$remaining / $total min',
                style: theme.textTheme.labelLarge?.copyWith(color: colour),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(height: 8, color: AppColors.border),
                AnimatedFractionallySizedBox(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  widthFactor: progress,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        colour.withValues(alpha: 0.6),
                        colour,
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small round glass button, used for back + re-centre over the map.
// ---------------------------------------------------------------------------
class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.85),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: AppColors.textPrimary, size: 20),
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
            Text('Map unavailable', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Google Maps API key is not configured.\n'
              'See README → "Google Maps API key" to enable.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
