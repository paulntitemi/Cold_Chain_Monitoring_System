import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/auth_provider.dart';
import 'providers/sensor_provider.dart';
import 'providers/shipment_provider.dart';
import 'screens/alerts/alert_screen.dart';
import 'screens/log/log_screen.dart';
import 'screens/map/map_screen.dart';
import 'screens/onboarding/start_trip_screen.dart';
import 'screens/trip/trip_screen.dart';
import 'theme/app_theme.dart';

class ColdTrackApp extends ConsumerWidget {
  const ColdTrackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Kick off the Cognito credential fetch on first build.
    ref.watch(cognitoBootstrapProvider);

    final router = _buildRouter(ref);

    return MaterialApp.router(
      title: 'ColdTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      routerConfig: router,
    );
  }

  GoRouter _buildRouter(WidgetRef ref) {
    return GoRouter(
      initialLocation: '/start',
      refreshListenable: _ShipmentListenable(ref),
      redirect: (context, state) {
        final hasTrip = ref.read(shipmentProvider) != null;
        final atStart = state.matchedLocation == '/start';
        if (hasTrip && atStart) return '/trip';
        if (!hasTrip && !atStart) return '/start';
        return null;
      },
      routes: [
        GoRoute(
          path: '/start',
          builder: (_, __) => const StartTripScreen(),
        ),
        ShellRoute(
          builder: (context, state, child) => _AppShell(child: child),
          routes: [
            GoRoute(path: '/trip', builder: (_, __) => const TripScreen()),
            GoRoute(
                path: '/alerts', builder: (_, __) => const AlertScreen()),
            GoRoute(path: '/map', builder: (_, __) => const MapScreen()),
            GoRoute(path: '/log', builder: (_, __) => const LogScreen()),
          ],
        ),
      ],
    );
  }
}

/// ChangeNotifier that rebuilds the router whenever the shipment state changes
/// — keeps `/start` ↔ `/trip` redirect in sync.
class _ShipmentListenable extends ChangeNotifier {
  _ShipmentListenable(WidgetRef ref) {
    ref.listen(shipmentProvider, (_, __) => notifyListeners());
  }
}

class _AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const _AppShell({required this.child});

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On resume, force-refresh the poll loop so the rider sees fresh data
    // immediately instead of waiting for the next 5s tick.
    if (state == AppLifecycleState.resumed) {
      final deviceId = ref.read(activeDeviceIdProvider);
      ref.read(sensorServiceProvider(deviceId)).forceRefresh();
    }
  }

  int _indexForLocation(String location) {
    if (location.startsWith('/alerts')) return 1;
    if (location.startsWith('/map')) return 2;
    if (location.startsWith('/log')) return 3;
    return 0;
  }

  void _onTap(int i) {
    switch (i) {
      case 0:
        context.go('/trip');
        break;
      case 1:
        context.go('/alerts');
        break;
      case 2:
        context.go('/map');
        break;
      case 3:
        context.go('/log');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final idx = _indexForLocation(location);

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx,
        onTap: _onTap,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.thermostat), label: 'Trip'),
          BottomNavigationBarItem(
              icon: Icon(Icons.notifications), label: 'Alerts'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(
              icon: Icon(Icons.history), label: 'Log'),
        ],
      ),
    );
  }
}

