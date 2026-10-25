import '../../data/models/hazard.dart';
import '../voice/voice_service.dart';

/// Guided voice reporting. The transcript is for review, not auto-submit.
class VoiceReportHelper {
  const VoiceReportHelper(this.voice);

  final VoiceService voice;

  Future<VoiceReportOutcome> captureDraft({
    void Function(String prediction)? onPrediction,
  }) async {
    await voice.speak(
      'Describe the hazard. You can name the type, such as blocked sidewalk, '
      'curb ramp, stairs, or crosswalk, and say what is wrong.',
    );
    final capture = await voice.listenOnce(
      timeout: const Duration(seconds: 20),
      onPrediction: onPrediction,
    );

    if (!capture.engineAvailable) {
      await voice.speak(
        'Speech recognition is unavailable. Use the form instead.',
      );
      return VoiceReportOutcome(
        message: capture.message ??
            'Google speech recognition is unavailable. Type the report instead.',
      );
    }

    if (!capture.hasTranscript) {
      await voice.speak('No speech was captured. You can try again or type the report.');
      return VoiceReportOutcome(
        message: capture.message ??
            'No speech was captured. Try again or type the note.',
      );
    }

    final text = capture.transcript!.trim();
    final category = _matchCategory(text);
    await voice.speak(
      'I heard: $text. Review the form, then submit. Nothing is sent yet.',
    );
    return VoiceReportOutcome(
      draft: VoiceReportDraft(category: category, description: text),
      message:
          'Transcript added for review. It is not submitted until you tap Submit.',
    );
  }

  HazardCategory? _matchCategory(String spoken) {
    final text = spoken.toLowerCase();
    for (final category in HazardCategory.values) {
      if (text.contains(category.shortLabel.toLowerCase()) ||
          text.contains(category.label.toLowerCase())) {
        return category;
      }
    }
    if (text.contains('sidewalk') ||
        text.contains('blocked') ||
        text.contains('obstruction') ||
        text.contains('cart')) {
      return HazardCategory.blockedSidewalk;
    }
    if (text.contains('ramp') || text.contains('curb')) {
      return HazardCategory.missingOrDamagedCurbRamp;
    }
    if (text.contains('stair') || text.contains('inaccessible')) {
      return HazardCategory.stairsOrInaccessiblePath;
    }
    if (text.contains('elevator')) {
      return HazardCategory.brokenElevator;
    }
    if (text.contains('pothole') || text.contains('pavement')) {
      return HazardCategory.potholeOrDamagedPavement;
    }
    if (text.contains('crosswalk') ||
        text.contains('crossing') ||
        text.contains('signal') ||
        text.contains('intersection')) {
      return HazardCategory.pedestrianSignalProblem;
    }
    if (text.contains('light') || text.contains('dark')) {
      return HazardCategory.poorLighting;
    }
    if (text.contains('construction') || text.contains('closed')) {
      return HazardCategory.constructionClosure;
    }
    return null;
  }
}

class VoiceReportOutcome {
  const VoiceReportOutcome({this.draft, required this.message});

  final VoiceReportDraft? draft;
  final String message;
}

class VoiceReportDraft {
  const VoiceReportDraft({
    required this.category,
    required this.description,
  });

  final HazardCategory? category;
  final String description;
}
