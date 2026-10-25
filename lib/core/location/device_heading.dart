import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Degrees clockwise from north, wrapped into `[0, 360)`.
double normalizeHeading(double degrees) {
  if (!degrees.isFinite) return 0;
  final wrapped = degrees % 360;
  return wrapped < 0 ? wrapped + 360 : wrapped;
}

double smallestHeadingDelta(double a, double b) {
  final delta = (normalizeHeading(a) - normalizeHeading(b)).abs();
  return delta > 180 ? 360 - delta : delta;
}

/// Arrow direction: GPS course, then compass, then north.
///
/// North (`0`) is used when neither sensor has a reading so the puck still
/// draws and nothing throws.
double displayHeadingDegrees({
  double? gpsCourse,
  double? compassDegrees,
}) {
  if (gpsCourse != null && gpsCourse.isFinite) {
    return normalizeHeading(gpsCourse);
  }
  if (compassDegrees != null && compassDegrees.isFinite) {
    return normalizeHeading(compassDegrees);
  }
  return 0;
}

/// Android rotation-vector stream. See `MainActivity` compass channel.
const compassChannelName = 'pathable/compass';

/// Compass heading in degrees clockwise from magnetic north.
///
/// A missing sensor or a desktop test yields one null event. Callers then
/// keep the GPS course, or point the arrow north.
final compassHeadingProvider = StreamProvider<double?>((ref) {
  const channel = EventChannel(compassChannelName);
  double? last;
  var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  return channel.receiveBroadcastStream().transform(
    StreamTransformer<dynamic, double?>.fromHandlers(
      handleData: (event, sink) {
        if (event is! num || !event.isFinite) return;
        final heading = normalizeHeading(event.toDouble());
        final now = DateTime.now();
        if (last != null &&
            smallestHeadingDelta(last!, heading) < 5 &&
            now.difference(lastEmit) < const Duration(milliseconds: 250)) {
          return;
        }
        last = heading;
        lastEmit = now;
        sink.add(heading);
      },
      handleError: (Object error, StackTrace stackTrace, EventSink<double?> sink) {
        sink.add(null);
        sink.close();
      },
    ),
  );
});
