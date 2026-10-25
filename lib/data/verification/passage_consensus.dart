import '../models/hazard.dart';

/// Crowd rule for adding and removing a reported problem.
///
/// A problem is added when at least 25% of distinct people who passed the spot
/// reported it (5 of 20). It is removed when at least 25% of those people say
/// it is gone. One person counts once.
class PassageConsensus {
  const PassageConsensus._();

  /// Share of passers required to add or remove a problem.
  static const agreementRatio = 0.25;

  /// Someone this close to a report counts as having passed it.
  static const passageRadiusMeters = 40.0;

  static const window = Duration(days: 30);

  static bool meetsAgreement(int part, int whole) {
    if (whole <= 0 || part <= 0) return false;
    final threshold = (agreementRatio * 1000).round();
    return part * 1000 >= whole * threshold;
  }

  static ConsensusDecision decide({
    required Set<String> passerIds,
    required Set<String> reporterIds,
    required Set<String> removerIds,
  }) {
    final reporters = reporterIds.where((id) => id.isNotEmpty).toSet();
    final removers = removerIds.where((id) => id.isNotEmpty).toSet();
    final passers = {
      ...passerIds.where((id) => id.isNotEmpty),
      ...reporters,
      ...removers,
    };

    if (passers.isEmpty) {
      return const ConsensusDecision(
        status: HazardStatus.provisional,
        reportShare: 0,
        removalShare: 0,
        passerCount: 0,
        reporterCount: 0,
        removerCount: 0,
      );
    }

    final reportShare = reporters.length / passers.length;
    final removalShare = removers.length / passers.length;
    final status = meetsAgreement(removers.length, passers.length)
        ? HazardStatus.resolved
        : meetsAgreement(reporters.length, passers.length)
            ? HazardStatus.active
            : HazardStatus.provisional;

    return ConsensusDecision(
      status: status,
      reportShare: reportShare.clamp(0, 1).toDouble(),
      removalShare: removalShare.clamp(0, 1).toDouble(),
      passerCount: passers.length,
      reporterCount: reporters.length,
      removerCount: removers.length,
    );
  }
}

class ConsensusDecision {
  const ConsensusDecision({
    required this.status,
    required this.reportShare,
    required this.removalShare,
    required this.passerCount,
    required this.reporterCount,
    required this.removerCount,
  });

  final HazardStatus status;
  final double reportShare;
  final double removalShare;
  final int passerCount;
  final int reporterCount;
  final int removerCount;
}
