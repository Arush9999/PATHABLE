import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Result of one speech capture from the recognizer.
class SpeechCapture {
  const SpeechCapture({
    required this.engineAvailable,
    this.transcript,
    this.message,
  });

  final bool engineAvailable;
  final String? transcript;

  /// Shown when the recognizer is missing or nothing was heard.
  final String? message;

  bool get hasTranscript =>
      transcript != null && transcript!.trim().isNotEmpty;
}

/// Abstraction over device speech input/output.
///
/// Speech recognition is only used for explicit reports.
/// Continuous background conversation recording is not supported.
abstract class VoiceService {
  Future<void> speak(String message);
  Future<void> stop();
  Future<void> stopSpeaking();
  Future<void> stopListening();
  Future<SpeechCapture> listenOnce({
    Duration timeout = const Duration(seconds: 8),
    void Function(String prediction)? onPrediction,
  });
  Future<void> hapticCue();
}

class DeviceVoiceService implements VoiceService {
  DeviceVoiceService({
    this.enabled = true,
    this.audioEnabled,
    FlutterTts? tts,
    SpeechToText? speech,
  })  : _tts = tts ?? FlutterTts(),
        _injectedSpeech = speech;

  /// Legacy gate. Prefer [audioEnabled], which reads the Audio setting live.
  bool enabled;

  /// When set, spoken output follows this check. The microphone still listens.
  final bool Function()? audioEnabled;
  final FlutterTts _tts;
  final SpeechToText? _injectedSpeech;
  SpeechToText? _speechClient;
  bool _speechReady = false;

  static const _googleSpeech = MethodChannel('pathable/google_speech');
  static const _googlePredictions = EventChannel('pathable/google_speech/partials');

  /// speech_to_text calls createSpeechRecognizer without a component, so a
  /// Samsung phone binds Samsung. Android listening uses the Google
  /// RecognitionService on pathable/google_speech instead.
  bool get _usesGoogleSpeech =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  SpeechToText _requireSpeech() =>
      _speechClient ??= _injectedSpeech ?? SpeechToText();

  bool get _canSpeak => audioEnabled?.call() ?? enabled;

  Future<void> _ensureTts() async {
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1);
    await _tts.setPitch(1);
    try {
      await _tts.setLanguage('en-US');
    } catch (error) {
      debugPrint('TTS language unavailable: $error');
    }
  }

  @override
  Future<void> speak(String message) async {
    if (!_canSpeak || message.trim().isEmpty) {
      return;
    }
    try {
      await _ensureTts();
      await _tts.speak(message);
    } catch (error) {
      debugPrint('TTS unavailable: $error');
    }
  }

  @override
  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  @override
  Future<void> stopListening() async {
    if (_usesGoogleSpeech) {
      try {
        await _googleSpeech.invokeMethod<void>('stop');
      } catch (error) {
        debugPrint('Google speech stop failed: $error');
      }
      return;
    }
    try {
      final speech = _requireSpeech();
      if (speech.isListening) {
        await speech.stop();
      }
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      await stopSpeaking();
      await stopListening();
    } catch (_) {}
  }

  @override
  Future<SpeechCapture> listenOnce({
    Duration timeout = const Duration(seconds: 8),
    void Function(String prediction)? onPrediction,
  }) async {
    if (_usesGoogleSpeech) {
      return _listenOnceWithGoogle(timeout, onPrediction);
    }
    return _listenOnceWithPlugin(timeout, onPrediction);
  }

  Future<SpeechCapture> _listenOnceWithGoogle(
    Duration timeout,
    void Function(String prediction)? onPrediction,
  ) async {
    const unavailable =
        'Install or enable the Google app to use speech recognition. '
        'Type the report instead.';
    final predictions = _googlePredictions.receiveBroadcastStream().listen(
      (event) {
        if (event is! String) return;
        final text = event.trim();
        if (text.isEmpty) return;
        onPrediction?.call(text);
      },
      onError: (Object error) => debugPrint('Speech prediction stopped: $error'),
    );
    try {
      final raw = await _googleSpeech.invokeMapMethod<String, dynamic>(
        'listen',
        {'timeoutMs': timeout.inMilliseconds},
      );
      if (raw == null) {
        return const SpeechCapture(
          engineAvailable: false,
          message: unavailable,
        );
      }
      final component = raw['component'];
      if (component is String && component.isNotEmpty) {
        debugPrint('Google speech component: $component');
      }
      final transcript = _nonEmpty(raw['transcript']);
      final message = _nonEmpty(raw['message']);
      return SpeechCapture(
        engineAvailable: raw['engineAvailable'] == true,
        transcript: transcript,
        message: message,
      );
    } catch (error) {
      debugPrint('Google speech recognition unavailable: $error');
      return SpeechCapture(
        engineAvailable: false,
        message: '$unavailable ($error)',
      );
    } finally {
      await predictions.cancel();
    }
  }

  Future<SpeechCapture> _listenOnceWithPlugin(
    Duration timeout,
    void Function(String prediction)? onPrediction,
  ) async {
    const unavailable =
        'Google speech recognition is unavailable on this device. '
        'Type the report instead.';
    final speech = _requireSpeech();

    try {
      if (!_speechReady) {
        _speechReady = await speech.initialize(
          onError: (error) => debugPrint('Speech error: $error'),
        );
      }
      if (!_speechReady) {
        return const SpeechCapture(
          engineAvailable: false,
          message: unavailable,
        );
      }

      var latest = '';
      await speech.listen(
        onResult: (value) {
          final words = value.recognizedWords.trim();
          if (words.isNotEmpty) {
            latest = words;
            onPrediction?.call(words);
          }
        },
        listenOptions: SpeechListenOptions(
          listenFor: timeout,
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          onDevice: false,
          listenMode: ListenMode.dictation,
        ),
      );

      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!speech.isListening) break;
      }
      if (speech.isListening) {
        await speech.stop();
      }

      final transcript = latest.trim();
      if (transcript.isEmpty) {
        return const SpeechCapture(
          engineAvailable: true,
          message: 'No speech was captured. Try again, or type the note.',
        );
      }
      return SpeechCapture(engineAvailable: true, transcript: transcript);
    } catch (error) {
      debugPrint('Speech recognition unavailable: $error');
      return SpeechCapture(
        engineAvailable: false,
        message: '$unavailable ($error)',
      );
    }
  }

  String? _nonEmpty(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Future<void> hapticCue() async {
    await HapticFeedback.mediumImpact();
  }
}
