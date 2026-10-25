import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/widgets/demo_banner.dart';
import '../../data/models/hazard_confirmation.dart';

class ConfirmHazardScreen extends ConsumerStatefulWidget {
  const ConfirmHazardScreen({super.key, required this.hazardId});

  final String hazardId;

  @override
  ConsumerState<ConfirmHazardScreen> createState() =>
      _ConfirmHazardScreenState();
}

class _ConfirmHazardScreenState extends ConsumerState<ConfirmHazardScreen> {
  ConfirmationResponse? _response;
  EvidenceType _evidence = EvidenceType.visual;
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    if (_response == null) {
      setState(() => _error = 'Choose whether the hazard is still present.');
      return;
    }

    final config = ref.read(appConfigurationProvider);
    if (config.requiresAccount &&
        ref.read(authSessionProvider).value == null) {
      if (!mounted) return;
      context.go(
        AppRoutes.accountWithNext(AppRoutes.confirm(widget.hazardId)),
      );
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref.read(hazardRepositoryProvider).confirm(
            hazardId: widget.hazardId,
            response: _response!,
            evidenceType: _evidence,
          );
      ref.invalidate(nearbyHazardsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(appConfigurationProvider).isDemoMode
                ? 'Confirmation saved in demonstration mode.'
                : 'Confirmation recorded.',
          ),
        ),
      );
      context.go(AppRoutes.hazard(widget.hazardId));
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigurationProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm hazard')),
      body: ListView(
        children: [
          if (config.isDemoMode) const DemoBanner(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Independent confirmations improve confidence. '
                  'One vote alone does not remove a serious hazard.',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                ...ConfirmationResponse.values.map(
                  (response) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ChoiceChip(
                      label: Text(response.label),
                      selected: _response == response,
                      onSelected: (_) => setState(() => _response = response),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text('Evidence type', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                DropdownMenu<EvidenceType>(
                  width: double.infinity,
                  initialSelection: _evidence,
                  label: const Text('How do you know?'),
                  dropdownMenuEntries: EvidenceType.values
                      .map(
                        (type) => DropdownMenuEntry(
                          value: type,
                          label: type.label,
                        ),
                      )
                      .toList(),
                  onSelected: (value) {
                    if (value != null) {
                      setState(() => _evidence = value);
                    }
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text(_submitting ? 'Saving…' : 'Submit confirmation'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
