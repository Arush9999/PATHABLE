import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import 'hey_pathable.dart';
import 'pathable_commands.dart';

/// Voice-only home for the Blind profile. Every other profile keeps the map.
class BlindAssistScreen extends ConsumerWidget {
  const BlindAssistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PathAble'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push(AppRoutes.settings),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: const HeyPathableMic(),
    );
  }
}

/// Microphone that waits for “Hey Pathable”, then answers the request.
class HeyPathableMic extends ConsumerStatefulWidget {
  const HeyPathableMic({super.key, this.headline});

  /// Current direction, shown as text. The map stays hidden.
  final String? headline;

  @override
  ConsumerState<HeyPathableMic> createState() => _HeyPathableMicState();
}

class _HeyPathableMicState extends ConsumerState<HeyPathableMic> {
  int _generation = 0;
  bool _awaiting = false;
  bool _predicting = false;
  String _status = 'Say Hey Pathable';
  final _prediction = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_loop());
  }

  @override
  void dispose() {
    _generation++;
    _prediction.dispose();
    unawaited(ref.read(voiceServiceProvider).stopListening());
    super.dispose();
  }

  void _showPrediction(String text, {bool? predicting}) {
    if (!mounted) return;
    final shown = preferPathableKeyword(text);
    _prediction.value = TextEditingValue(
      text: shown,
      selection: TextSelection.collapsed(offset: shown.length),
    );
    if (predicting != null && predicting != _predicting) {
      setState(() => _predicting = predicting);
    }
  }

  Future<void> _loop() async {
    final generation = _generation;
    final voice = ref.read(voiceServiceProvider);
    if (ref.read(accessibilityProfileProvider).preferences.spokenInstructions) {
      await voice.speak('Say Hey Pathable.');
    }
    while (mounted && generation == _generation) {
      _prediction.clear();
      setState(() => _predicting = true);
      final capture = await voice.listenOnce(
        timeout: const Duration(seconds: 12),
        onPrediction: (text) {
          if (!mounted || generation != _generation) return;
          _showPrediction(text, predicting: true);
        },
      );
      if (!mounted || generation != _generation) return;
      setState(() => _predicting = false);
      final transcript = (capture.transcript?.trim().isNotEmpty ?? false)
          ? capture.transcript!.trim()
          : _prediction.text.trim();
      if (transcript.isNotEmpty) {
        _showPrediction(transcript, predicting: false);
      }
      if (transcript.isEmpty) {
        if (capture.message != null && !capture.engineAvailable) {
          setState(() => _status = capture.message!);
          await Future<void>.delayed(const Duration(seconds: 3));
        }
        continue;
      }
      final request = interpretPathableSpeech(
        transcript,
        awaitingCommand: _awaiting,
      );
      if (request == null) {
        setState(() => _status = 'Heard: ${preferPathableKeyword(transcript)}');
        continue;
      }
      _awaiting = request.intent == PathableIntent.followUp;
      final reply = await answerPathableRequest(ref, context, request);
      if (!mounted || generation != _generation) return;
      setState(() => _status = reply);
      await voice.speak(reply);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audio =
        ref.watch(accessibilityProfileProvider).preferences.spokenInstructions;
    final headline = widget.headline;

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Icon(
                Icons.mic,
                size: 96,
                color: theme.colorScheme.primary,
                semanticLabel: 'Microphone. Say Hey Pathable.',
              ),
              const SizedBox(height: 20),
              Text(
                'Say Hey Pathable',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _prediction,
                readOnly: true,
                minLines: 2,
                maxLines: 4,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontStyle: _predicting ? FontStyle.italic : FontStyle.normal,
                  color: _predicting
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  labelText: _predicting ? 'Hearing…' : 'Heard',
                  hintText: 'Words appear here as you speak',
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (headline != null && headline.isNotEmpty) ...[
                Text(
                  headline,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                _status,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const Spacer(),
              Text(
                audio ? 'Audio on' : 'Audio off. No sound.',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
