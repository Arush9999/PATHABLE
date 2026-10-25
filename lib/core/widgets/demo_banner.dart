import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Persistent banner clarifying that demonstration data is not real-world data.
class DemoBanner extends StatelessWidget {
  const DemoBanner({
    super.key,
    this.message =
        'Demonstration mode — fictional data, not verified real-world reports.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: PathAbleTheme.demoBanner,
      child: SafeArea(
        bottom: false,
        child: Semantics(
          liveRegion: true,
          label: message,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.science_outlined,
                    color: Colors.white,
                    size: 16,
                    semanticLabel: 'Demonstration mode',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
