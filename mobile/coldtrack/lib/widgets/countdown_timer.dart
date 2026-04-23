import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Count-down timer that ticks once per second and is colour-coded by the
/// provided [RiskLevel]. Used to surface remaining safe minutes on trip
/// screen and alert cards.
class CountdownTimer extends StatefulWidget {
  final int initialSeconds;
  final RiskLevel level;
  final String label;

  const CountdownTimer({
    super.key,
    required this.initialSeconds,
    required this.level,
    this.label = 'Safe time remaining',
  });

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer> {
  late int _secondsLeft;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.initialSeconds;
    _start();
  }

  @override
  void didUpdateWidget(covariant CountdownTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSeconds != oldWidget.initialSeconds) {
      setState(() => _secondsLeft = widget.initialSeconds);
    }
  }

  void _start() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_secondsLeft > 0) _secondsLeft--;
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = widget.level.color;
    final minutes = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsLeft % 60).toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          '$minutes:$seconds',
          style: theme.textTheme.displayMedium?.copyWith(
            color: colour,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
