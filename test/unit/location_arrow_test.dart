import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pathable/core/location/device_heading.dart';
import 'package:pathable/features/map/user_location_arrow.dart';
import 'package:pathable/routing/reroute_gate.dart';

void main() {
  test('display heading prefers GPS course over the compass', () {
    expect(
      displayHeadingDegrees(gpsCourse: 90, compassDegrees: 180),
      90,
    );
  });

  test('display heading uses the compass when GPS course is missing', () {
    expect(
      displayHeadingDegrees(gpsCourse: null, compassDegrees: -90),
      270,
    );
  });

  test('display heading points north when neither sensor has a reading', () {
    expect(displayHeadingDegrees(), 0);
    expect(
      displayHeadingDegrees(gpsCourse: double.nan, compassDegrees: double.nan),
      0,
    );
  });

  test('one off-route fix does not request a new route', () {
    final gate = RerouteGate();
    final now = DateTime.utc(2026, 10, 25, 12);
    expect(gate.shouldRequest(offRoute: true, now: now), isFalse);
    expect(gate.shouldRequest(offRoute: true, now: now), isFalse);
    expect(gate.shouldRequest(offRoute: true, now: now), isTrue);
  });

  test('an on-route fix clears the off-route streak', () {
    final gate = RerouteGate();
    final now = DateTime.utc(2026, 10, 25, 12);
    expect(gate.shouldRequest(offRoute: true, now: now), isFalse);
    expect(gate.shouldRequest(offRoute: true, now: now), isFalse);
    expect(gate.shouldRequest(offRoute: false, now: now), isFalse);
    expect(gate.shouldRequest(offRoute: true, now: now), isFalse);
    expect(gate.shouldRequest(offRoute: true, now: now), isFalse);
    expect(gate.shouldRequest(offRoute: true, now: now), isTrue);
  });

  test('a reroute waits 20 seconds and then needs a fresh streak', () {
    final gate = RerouteGate();
    final start = DateTime.utc(2026, 10, 25, 12);
    expect(gate.shouldRequest(offRoute: true, now: start), isFalse);
    expect(gate.shouldRequest(offRoute: true, now: start), isFalse);
    expect(gate.shouldRequest(offRoute: true, now: start), isTrue);
    gate.markStarted(start);
    gate.markFinished();

    final soon = start.add(const Duration(seconds: 19));
    expect(gate.shouldRequest(offRoute: true, now: soon), isFalse);
    expect(gate.shouldRequest(offRoute: true, now: soon), isFalse);
    expect(gate.shouldRequest(offRoute: true, now: soon), isFalse);

    final later = start.add(const Duration(seconds: 20));
    expect(gate.shouldRequest(offRoute: true, now: later), isFalse);
    expect(gate.shouldRequest(offRoute: true, now: later), isFalse);
    expect(gate.shouldRequest(offRoute: true, now: later), isTrue);
  });

  test('an in-flight reroute is not started again', () {
    final gate = RerouteGate();
    final start = DateTime.utc(2026, 10, 25, 12);
    expect(gate.shouldRequest(offRoute: true, now: start), isFalse);
    expect(gate.shouldRequest(offRoute: true, now: start), isFalse);
    expect(gate.shouldRequest(offRoute: true, now: start), isTrue);
    gate.markStarted(start);
    final later = start.add(const Duration(seconds: 30));
    expect(gate.shouldRequest(offRoute: true, now: later), isFalse);
    gate.markFinished();
    expect(gate.shouldRequest(offRoute: true, now: later), isFalse);
    expect(gate.shouldRequest(offRoute: true, now: later), isFalse);
    expect(gate.shouldRequest(offRoute: true, now: later), isTrue);
  });

  test('location arrow image decodes as a png', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = locationArrowPng();
    expect(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 64);
    expect(frame.image.height, 64);
    frame.image.dispose();
    codec.dispose();
  });
}
