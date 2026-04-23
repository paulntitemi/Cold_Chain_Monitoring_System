import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/env.dart';
import '../../providers/shipment_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dot_grid_background.dart';

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
    final screen = MediaQuery.sizeOf(context);

    return Scaffold(
      body: DotGridBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: screen.height - 64,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 32),
                    const _ColdChainMark(),
                    const SizedBox(height: 28),
                    Text(
                      'ColdTrack',
                      style: theme.textTheme.displayMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Cold-chain vaccine monitoring',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 36),
                    _FormCard(
                      riderCtrl: _riderCtrl,
                      deviceCtrl: _deviceCtrl,
                      vaccineCtrl: _vaccineCtrl,
                      destinationCtrl: _destinationCtrl,
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: _startTrip,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text('Start Monitoring'),
                          SizedBox(width: 6),
                          Icon(Icons.arrow_forward, size: 18),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Safe range 2°C – 8°C · monitored every 5s',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Logo mark — thermometer inside a location pin, in teal.
// ---------------------------------------------------------------------------
class _ColdChainMark extends StatefulWidget {
  const _ColdChainMark();

  @override
  State<_ColdChainMark> createState() => _ColdChainMarkState();
}

class _ColdChainMarkState extends State<_ColdChainMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final glow = 0.2 + 0.4 * _ctrl.value;
        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Pin backdrop
              Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: glow),
                      blurRadius: 40,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.18),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.6),
                  ),
                ),
              ),
              const Icon(Icons.thermostat,
                  size: 38, color: AppColors.primary),
              // Location pin notch
              Positioned(
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.7),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Rounded form card
// ---------------------------------------------------------------------------
class _FormCard extends StatelessWidget {
  final TextEditingController riderCtrl;
  final TextEditingController deviceCtrl;
  final TextEditingController vaccineCtrl;
  final TextEditingController destinationCtrl;

  const _FormCard({
    required this.riderCtrl,
    required this.deviceCtrl,
    required this.vaccineCtrl,
    required this.destinationCtrl,
  });

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _Field(
            controller: riderCtrl,
            label: 'Rider name',
            icon: Icons.person,
            validator: _required,
          ),
          const SizedBox(height: 14),
          _Field(
            controller: deviceCtrl,
            label: 'IoT device ID',
            icon: Icons.sensors,
            validator: _required,
          ),
          const SizedBox(height: 14),
          _Field(
            controller: vaccineCtrl,
            label: 'Vaccine type',
            icon: Icons.medical_services,
            validator: _required,
          ),
          const SizedBox(height: 14),
          _Field(
            controller: destinationCtrl,
            label: 'Destination',
            icon: Icons.location_on,
            validator: _required,
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 18),
      ),
    );
  }
}
