import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/widgets/accessible_icon_label.dart';
import '../../core/widgets/demo_banner.dart';
import '../../data/models/hazard.dart';

class HazardDetailScreen extends ConsumerWidget {
  const HazardDetailScreen({super.key, required this.hazardId});

  final String hazardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigurationProvider);

    return FutureBuilder(
      future: ref.read(hazardRepositoryProvider).getById(hazardId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final hazard = snapshot.data;
        if (hazard == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Hazard not found')),
            body: Center(
              child: FilledButton(
                onPressed: () => context.go(AppRoutes.map),
                child: const Text('Return to map'),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(hazard.category.shortLabel),
          ),
          body: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (config.isDemoMode || hazard.isDemonstration)
                const DemoBanner(
                  message:
                      'Demonstration hazard — not a verified real-world report.',
                ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hazard.category.label,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    const SizedBox(height: 12),
                    AccessibleIconLabel(
                      icon: _statusIcon(hazard.status),
                      label: 'Status: ${hazard.status.label}',
                    ),
                    const SizedBox(height: 8),
                    AccessibleIconLabel(
                      icon: Icons.priority_high,
                      label: 'Severity: ${hazard.severity.label}',
                    ),
                    const SizedBox(height: 8),
                    AccessibleIconLabel(
                      icon: Icons.verified_outlined,
                      label:
                          'Confidence: ${(hazard.confidenceScore * 100).round()}%',
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Description',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      hazard.description?.isNotEmpty == true
                          ? hazard.description!
                          : 'No description provided.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (hazard.photoPath != null &&
                        _isLocalPhoto(hazard.photoPath!)) ...[
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(hazard.photoPath!),
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _MetaRow(
                      label: 'Reported',
                      value: _format(hazard.createdAt),
                    ),
                    _MetaRow(
                      label: 'Last confirmed',
                      value: hazard.lastConfirmedAt == null
                          ? 'Not yet confirmed'
                          : _format(hazard.lastConfirmedAt!),
                    ),
                    _MetaRow(
                      label: 'Location',
                      value:
                          '${hazard.location.latitude.toStringAsFixed(5)}, '
                          '${hazard.location.longitude.toStringAsFixed(5)}',
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Unresolved reports are not shown as confirmed facts.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () =>
                          context.push(AppRoutes.confirm(hazard.id)),
                      icon: const Icon(Icons.how_to_vote_outlined),
                      label: const Text('Confirm or update status'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static bool _isLocalPhoto(String path) {
    if (path.startsWith('http')) return false;
    return File(path).existsSync();
  }

  static IconData _statusIcon(HazardStatus status) => switch (status) {
        HazardStatus.active => Icons.check_circle_outline,
        HazardStatus.provisional => Icons.pending_outlined,
        HazardStatus.resolved => Icons.task_alt,
        HazardStatus.stale => Icons.history,
        HazardStatus.underReview => Icons.rate_review_outlined,
      };

  static String _format(DateTime value) {
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
