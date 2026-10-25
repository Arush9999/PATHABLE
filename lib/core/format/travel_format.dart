/// Human-friendly distance / duration formatting for directions UI.
abstract final class TravelFormat {
  static String distance(double meters) {
    final miles = meters / 1609.344;
    if (miles < 0.1) {
      final feet = meters * 3.28084;
      return '${feet.round()} ft';
    }
    if (miles < 10) {
      return '${miles.toStringAsFixed(1)} mi';
    }
    return '${miles.toStringAsFixed(0)} mi';
  }

  static String duration(double seconds) {
    final totalMinutes = (seconds / 60).round().clamp(1, 24 * 60);
    if (totalMinutes < 60) {
      return '$totalMinutes min';
    }
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (minutes == 0) {
      return '$hours hr';
    }
    return '$hours hr $minutes min';
  }

  static String etaClock(double durationSeconds, {DateTime? now}) {
    final arrival =
        (now ?? DateTime.now()).add(Duration(seconds: durationSeconds.round()));
    final hour = arrival.hour % 12 == 0 ? 12 : arrival.hour % 12;
    final minute = arrival.minute.toString().padLeft(2, '0');
    final period = arrival.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  static String summaryLine(double meters, double seconds) {
    return '${distance(meters)} · ${duration(seconds)} · ETA ${etaClock(seconds)}';
  }
}
