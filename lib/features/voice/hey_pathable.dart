/// What a traveler asked after saying “Hey Pathable”.
enum PathableIntent {
  followUp,
  navigate,
  whereAmI,
  farther,
  repeat,
  report,
  stop,
  help,
  unknown,
}

class HeardRequest {
  const HeardRequest(this.intent, {this.place});

  final PathableIntent intent;
  final String? place;
}

/// Pulls a command out of one speech transcript.
///
/// Returns null when the phrase did not start with the wake words and
/// PathAble is not already waiting for the rest of the question.
/// Google often hears the name as “hey possible”. Treat that, and the
/// name itself, as the PathAble keyword.
String preferPathableKeyword(String heard) {
  var text = heard;
  const misheard = [
    'hey pathable',
    'hey path able',
    'hey pathabel',
    'hey path of all',
    'hey possible',
    'hey passable',
    'hey pass able',
    'a pathable',
    'path able',
    'pathable',
  ];
  for (final phrase in misheard) {
    text = text.replaceAll(
      RegExp('\\b$phrase\\b', caseSensitive: false),
      'PathAble',
    );
  }
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

HeardRequest? interpretPathableSpeech(
  String transcript, {
  required bool awaitingCommand,
}) {
  final body = _commandBody(
    preferPathableKeyword(transcript),
    awaitingCommand: awaitingCommand,
  );
  if (body == null) return null;
  if (body.isEmpty) {
    return const HeardRequest(PathableIntent.followUp);
  }
  return _parseCommand(body);
}

String? _commandBody(String transcript, {required bool awaitingCommand}) {
  final lower = transcript
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (lower.isEmpty) return null;

  const wakes = ['hey pathable', 'pathable'];
  for (final wake in wakes) {
    final index = lower.indexOf(wake);
    if (index < 0) continue;
    return lower.substring(index + wake.length).trim();
  }
  if (awaitingCommand) return lower;
  return null;
}

HeardRequest _parseCommand(String command) {
  const help = {
    'help',
    'what can i say',
    'what can you do',
  };
  const stop = {
    'stop',
    'cancel',
    'end',
    'end navigation',
    'stop navigation',
  };
  const where = {
    'where am i',
    'where am i now',
    'what is my location',
    'whats my location',
  };
  const farther = {
    'how far',
    'how much farther',
    'how much further',
    'how long',
    'whats next',
    'what is next',
    'what next',
  };
  const repeat = {
    'repeat',
    'say that again',
    'repeat that',
  };
  const report = {
    'report',
    'report a hazard',
    'report hazard',
    'report a problem',
  };

  if (help.contains(command)) {
    return const HeardRequest(PathableIntent.help);
  }
  if (stop.contains(command)) {
    return const HeardRequest(PathableIntent.stop);
  }
  if (where.contains(command)) {
    return const HeardRequest(PathableIntent.whereAmI);
  }
  if (farther.contains(command)) {
    return const HeardRequest(PathableIntent.farther);
  }
  if (repeat.contains(command)) {
    return const HeardRequest(PathableIntent.repeat);
  }
  if (report.contains(command)) {
    return const HeardRequest(PathableIntent.report);
  }

  final navigate = RegExp(
    r'^(?:please )?(?:take me to|directions to|navigate to|go to|walk to|guide me to)\s+(.+)$',
  ).firstMatch(command);
  if (navigate != null) {
    return HeardRequest(PathableIntent.navigate, place: navigate.group(1));
  }

  if (command.length >= 3) {
    return HeardRequest(PathableIntent.navigate, place: command);
  }
  return HeardRequest(PathableIntent.unknown, place: command);
}
