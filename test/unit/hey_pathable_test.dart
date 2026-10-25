import 'package:flutter_test/flutter_test.dart';
import 'package:pathable/features/voice/hey_pathable.dart';

void main() {
  test('ignores speech that does not start with Hey Pathable', () {
    expect(
      interpretPathableSpeech('what time is it', awaitingCommand: false),
      isNull,
    );
  });

  test('wake phrase alone asks for the rest of the request', () {
    final heard = interpretPathableSpeech(
      'Hey Pathable',
      awaitingCommand: false,
    );
    expect(heard?.intent, PathableIntent.followUp);
  });

  test('take me to keeps the place name', () {
    final heard = interpretPathableSpeech(
      'Hey Pathable, take me to the library',
      awaitingCommand: false,
    );
    expect(heard?.intent, PathableIntent.navigate);
    expect(heard?.place, 'the library');
  });

  test('a follow-up phrase does not need the wake words again', () {
    final heard = interpretPathableSpeech(
      'the grocery store',
      awaitingCommand: true,
    );
    expect(heard?.intent, PathableIntent.navigate);
    expect(heard?.place, 'the grocery store');
  });

  test('hey possible is the PathAble keyword', () {
    expect(preferPathableKeyword('hey possible'), 'PathAble');
    final heard = interpretPathableSpeech(
      'hey possible take me to the library',
      awaitingCommand: false,
    );
    expect(heard?.intent, PathableIntent.navigate);
    expect(heard?.place, 'the library');
  });

  test('where am I and stop are exact requests', () {
    expect(
      interpretPathableSpeech('hey path able where am i', awaitingCommand: false)
          ?.intent,
      PathableIntent.whereAmI,
    );
    expect(
      interpretPathableSpeech('Hey Pathable stop', awaitingCommand: false)
          ?.intent,
      PathableIntent.stop,
    );
  });
}
