import 'package:intl/intl.dart';

extension DateTimeX on DateTime {
  /// Returns "Xs ago", "Xm ago", "Xh ago" style relative time strings.
  String get relativeToNow {
    final diff = DateTime.now().difference(this);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String get hhmmss => DateFormat('HH:mm:ss').format(this);
  String get hhmm => DateFormat('HH:mm').format(this);
  String get isoShort => DateFormat('MMM d, HH:mm').format(this);
}

extension DoubleX on double {
  String toFixed(int digits) => toStringAsFixed(digits);
}

extension DurationX on Duration {
  String get mmss {
    final m = inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
