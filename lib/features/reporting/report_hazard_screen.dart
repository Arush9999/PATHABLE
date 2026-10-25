import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/widgets/demo_banner.dart';
import '../../data/local/demo_data.dart';
import '../../data/local/pending_report_queue.dart';
import '../../data/models/geo_point.dart';
import '../../data/models/hazard.dart';
import 'report_validators.dart';
import 'voice_report_helper.dart';

class ReportHazardScreen extends ConsumerStatefulWidget {
  const ReportHazardScreen({super.key});

  @override
  ConsumerState<ReportHazardScreen> createState() => _ReportHazardScreenState();
}

class _ReportHazardScreenState extends ConsumerState<ReportHazardScreen> {
  final _descriptionController = TextEditingController();
  final _validators = const ReportValidators();

  HazardCategory? _category;
  HazardSeverity _severity = HazardSeverity.moderate;
  GeoPoint? _location;
  String? _locationError;
  List<String> _errors = const [];
  List<Hazard> _duplicates = const [];
  bool _submitting = false;
  bool _acknowledgedDuplicates = false;
  bool _listening = false;
  bool _usingDemoLocation = false;
  String? _photoPath;
  String? _speechMessage;

  @override
  void initState() {
    super.initState();
    _bootstrapLocation();
  }

  Future<void> _bootstrapLocation() async {
    final config = ref.read(appConfigurationProvider);
    try {
      final point =
          await ref.read(locationServiceProvider).getCurrentPosition();
      if (!mounted) return;
      ref.read(userLocationProvider.notifier).publish(point);
      setState(() {
        _location = point;
        _usingDemoLocation = false;
        _locationError = null;
      });
    } catch (error) {
      if (!mounted) return;
      final notice = ref.read(locationNoticeProvider) ?? error.toString();
      if (config.isDemoMode) {
        setState(() {
          _location = DemoData.startLocation;
          _usingDemoLocation = true;
          _locationError =
              '$notice Demonstration mode is using the Riverstone sample pin, not a GPS fix.';
        });
      } else {
        setState(() {
          _location = null;
          _usingDemoLocation = false;
          _locationError = notice;
        });
      }
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _startVoiceReport() async {
    if (_listening) return;
    setState(() {
      _listening = true;
      _speechMessage = 'Listening… words appear in the note as you speak.';
    });
    final outcome = await VoiceReportHelper(ref.read(voiceServiceProvider))
        .captureDraft(
      onPrediction: (text) {
        if (!mounted) return;
        _descriptionController.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      },
    );
    if (!mounted) return;
    setState(() {
      _listening = false;
      _speechMessage = outcome.message;
      final draft = outcome.draft;
      if (draft != null) {
        if (draft.category != null) _category = draft.category;
        _descriptionController.text = draft.description;
        _acknowledgedDuplicates = false;
      }
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file == null) {
      return;
    }
    setState(() => _photoPath = file.path);
  }

  Future<void> _choosePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    await _pickPhoto(source);
  }

  Future<void> _submit() async {
    final config = ref.read(appConfigurationProvider);
    if (config.requiresAccount &&
        ref.read(authSessionProvider).value == null) {
      if (!mounted) return;
      context.go(AppRoutes.accountWithNext(AppRoutes.report));
      return;
    }

    final description = _descriptionController.text;
    final validation = _validators.validate(
      category: _category,
      severity: _severity,
      location: _location,
      description: description,
    );

    if (!validation.isValid) {
      setState(() => _errors = validation.errors);
      return;
    }

    final repo = ref.read(hazardRepositoryProvider);
    final existing = await repo.getNearbyHazards(
      center: _location!,
      radiusMeters: 250,
    );
    final duplicates = _validators.findLikelyDuplicates(
      existing: existing,
      location: _location!,
      category: _category!,
    );

    if (duplicates.isNotEmpty && !_acknowledgedDuplicates) {
      setState(() {
        _duplicates = duplicates;
        _errors = [
          'A similar report may already exist nearby. Review it, or confirm '
              'you still want to submit a new report.',
        ];
      });
      return;
    }

    setState(() {
      _submitting = true;
      _errors = const [];
    });

    try {
      final now = DateTime.now().toUtc();
      final note = description.trim().isEmpty
          ? _category!.label
          : description.trim();
      final draft = Hazard(
        id: '',
        category: _category!,
        severity: _severity,
        status: HazardStatus.provisional,
        location: _location!,
        confidenceScore: 0.35,
        createdAt: now,
        updatedAt: now,
        description: config.isDemoMode ? '[DEMO] $note' : note,
        photoPath: _photoPath,
        isDemonstration: config.isDemoMode,
      );

      final created = await repo.create(draft);

      ref.invalidate(nearbyHazardsProvider);
      if (!mounted) return;
      final view = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Report submitted'),
          content: Text(
            config.isDemoMode
                ? 'Saved on this device as a demonstration report. '
                    'It is not a verified real-world hazard.'
                : 'Your report was saved and starts as provisionally reported. '
                    'Others can confirm it from the map.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('View report'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (view == true) {
        context.go(AppRoutes.hazard(created.id));
      } else {
        context.go(AppRoutes.map);
      }
    } catch (error) {
      // Do not claim success. Queue locally until connectivity/backend accepts.
      final prefs = ref.read(sharedPreferencesProvider);
      final queued = await PendingReportQueue(prefs).enqueue(
        Hazard(
          id: '',
          category: _category!,
          severity: _severity,
          status: HazardStatus.provisional,
          location: _location!,
          confidenceScore: 0.35,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
          description: _descriptionController.text.trim(),
          photoPath: _photoPath,
          isDemonstration: ref.read(appConfigurationProvider).isDemoMode,
        ),
      );
      setState(() {
        _errors = [
          'Server did not accept the report yet. Saved as a local draft '
          '(${queued.id}) — not marked submitted. Error: $error',
        ];
      });
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
      appBar: AppBar(
        title: const Text('Report a hazard'),
        actions: [
          IconButton(
            tooltip: 'Speak a hazard report',
            onPressed: _listening ? null : _startVoiceReport,
            icon: Icon(_listening ? Icons.mic : Icons.mic_none),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (config.isDemoMode) const DemoBanner(),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick report. No photo required. Speak or tap a type, '
                  'review the details, then submit.',
                  style: theme.textTheme.bodyLarge,
                ),
                if (_speechMessage != null) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.record_voice_over_outlined,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _speechMessage!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text('What is the problem?', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: HazardCategory.values
                      .map(
                        (category) => ChoiceChip(
                          label: Text(category.shortLabel),
                          selected: _category == category,
                          onSelected: (_) {
                            setState(() {
                              _category = category;
                              _acknowledgedDuplicates = false;
                            });
                          },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 20),
                Text('How bad is it?', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: HazardSeverity.values
                      .map(
                        (severity) => ChoiceChip(
                          label: Text(severity.label),
                          selected: _severity == severity,
                          onSelected: (_) {
                            setState(() => _severity = severity);
                          },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                Text(
                  _location == null
                      ? 'Waiting for a GPS fix…'
                      : _usingDemoLocation
                          ? 'Sample pin, not a GPS fix'
                          : 'GPS location',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_location != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_location!.latitude.toStringAsFixed(5)}, '
                    '${_location!.longitude.toStringAsFixed(5)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (_locationError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _locationError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                TextButton(
                  onPressed: _bootstrapLocation,
                  child: const Text('Refresh location'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descriptionController,
                  maxLines: 3,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Optional note',
                    hintText: 'Spoken text appears here for review',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _choosePhoto,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(
                    _photoPath == null
                        ? 'Attach photo (optional)'
                        : 'Photo attached — tap to replace',
                  ),
                ),
                if (_photoPath != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(_photoPath!),
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                if (_duplicates.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Possible duplicates',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ..._duplicates.map(
                    (hazard) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(hazard.category.label),
                      subtitle: Text(hazard.description ?? hazard.status.label),
                      trailing: TextButton(
                        onPressed: () =>
                            context.push(AppRoutes.hazard(hazard.id)),
                        child: const Text('Open'),
                      ),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _acknowledgedDuplicates,
                    onChanged: (value) {
                      setState(() => _acknowledgedDuplicates = value ?? false);
                    },
                    title: const Text('Submit a new report anyway'),
                  ),
                ],
                if (_errors.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ..._errors.map(
                    (error) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        error,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_submitting ? 'Submitting…' : 'Submit report'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
