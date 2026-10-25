/// Decides when an off-route traveler should get a new path.
///
/// One bad GPS point is ignored. A request starts only after several
/// consecutive off-route fixes, and not again until [cooldown] has passed.
class RerouteGate {
  int streak = 0;
  DateTime? lastAttempt;
  bool inFlight = false;

  static const fixesRequired = 3;
  static const cooldown = Duration(seconds: 20);

  bool shouldRequest({
    required bool offRoute,
    required DateTime now,
    int fixesRequired = RerouteGate.fixesRequired,
    Duration cooldown = RerouteGate.cooldown,
  }) {
    if (!offRoute) {
      streak = 0;
      return false;
    }
    if (inFlight) return false;
    final last = lastAttempt;
    if (last != null && now.difference(last) < cooldown) return false;
    streak += 1;
    return streak >= fixesRequired;
  }

  void markStarted(DateTime now) {
    lastAttempt = now;
    inFlight = true;
    streak = 0;
  }

  void markFinished() {
    inFlight = false;
  }
}
