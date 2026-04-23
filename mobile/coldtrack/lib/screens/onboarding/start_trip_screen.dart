import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/env.dart';
import '../../providers/shipment_provider.dart';
import '../../theme/app_theme.dart';

class StartTripScreen extends ConsumerStatefulWidget {
  const StartTripScreen({super.key});

  @override
  ConsumerState<StartTripScreen> createState() => _StartTripScreenState();
}

class _StartTripScreenState extends ConsumerState<StartTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _riderCtrl = TextEditingController();
  final _deviceCtrl = TextEditingController();
  final _vaccineCtrl = TextEditingController(text: 'RSV');
  final _destinationCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _deviceCtrl.text = Env.defaultDeviceId;
  }

  @override
  void dispose() {
    _riderCtrl.dispose();
    _deviceCtrl.dispose();
    _vaccineCtrl.dispose();
    _destinationCtrl.dispose();
    super.dispose();
  }

  void _startTrip() {
    if (!_formKey.currentState!.validate()) return;

    ref.read(shipmentProvider.notifier).startTrip(
          deviceId: _deviceCtrl.text.trim(),
          riderName: _riderCtrl.text.trim(),
          vaccineType: _vaccineCtrl.text.trim(),
          destination: _destinationCtrl.text.trim(),
        );

    if (!mounted) return;
    context.go('/trip');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                Icon(Icons.local_shipping,
                    size: 56, color: AppColors.primary),
                const SizedBox(height: 16),
                Text('ColdTrack', style: theme.textTheme.displayMedium),
                const SizedBox(height: 4),
                Text(
                  'Start a new cold-chain trip',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 40),
                _field(
                  controller: _riderCtrl,
                  label: 'Rider name',
                  icon: Icons.person,
                  validator: _required,
                ),
                const SizedBox(height: 16),
                _field(
                  controller: _deviceCtrl,
                  label: 'IoT device ID',
                  icon: Icons.sensors,
                  validator: _required,
                ),
                const SizedBox(height: 16),
                _field(
                  controller: _vaccineCtrl,
                  label: 'Vaccine type',
                  icon: Icons.medical_services,
                  validator: _required,
                ),
                const SizedBox(height: 16),
                _field(
                  controller: _destinationCtrl,
                  label: 'Destination',
                  icon: Icons.location_on,
                  validator: _required,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _startTrip,
                  child: const Text('START TRIP'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Safe temperature range: 2°C to 8°C',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.textSecondary),
      ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;
}
