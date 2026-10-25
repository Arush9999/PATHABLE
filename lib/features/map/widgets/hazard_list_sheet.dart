import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/accessible_icon_label.dart';
import '../../../data/models/hazard.dart';

/// Accessible list of nearby hazards for users who do not rely on the map alone.
class HazardListSheet extends StatelessWidget {
  const HazardListSheet({
    super.key,
    required this.hazards,
    this.onSelect,
  });

  final List<Hazard> hazards;
  final ValueChanged<Hazard>? onSelect;

  @override
  Widget build(BuildContext context) {
    if (hazards.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No hazards in the current map area.'),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: hazards.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final hazard = hazards[index];
        return ListTile(
          isThreeLine: true,
          leading: Icon(_iconFor(hazard.category)),
          title: Text(hazard.category.label),
          subtitle: Text(
            '${hazard.status.label} · ${hazard.severity.label}'
            '${hazard.isDemonstration ? ' · Demonstration data' : ''}\n'
            '${hazard.description ?? ''}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            onSelect?.call(hazard);
            context.push(AppRoutes.hazard(hazard.id));
          },
        );
      },
    );
  }

  static IconData _iconFor(HazardCategory category) => switch (category) {
        HazardCategory.blockedSidewalk => Icons.block,
        HazardCategory.potholeOrDamagedPavement => Icons.warning_amber,
        HazardCategory.missingOrDamagedCurbRamp => Icons.accessible_forward,
        HazardCategory.stairsOrInaccessiblePath => Icons.stairs,
        HazardCategory.brokenElevator => Icons.elevator,
        HazardCategory.constructionClosure => Icons.construction,
        HazardCategory.poorLighting => Icons.wb_sunny_outlined,
        HazardCategory.excessiveNoise => Icons.volume_up,
        HazardCategory.pedestrianSignalProblem => Icons.traffic,
        HazardCategory.other => Icons.report_outlined,
      };
}

class HazardStatusLegend extends StatelessWidget {
  const HazardStatusLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        AccessibleIconLabel(
          dense: true,
          icon: Icons.check_circle_outline,
          label: 'Confirmed active',
        ),
        AccessibleIconLabel(
          dense: true,
          icon: Icons.pending_outlined,
          label: 'Provisional',
        ),
        AccessibleIconLabel(
          dense: true,
          icon: Icons.history,
          label: 'Stale',
        ),
      ],
    );
  }
}
