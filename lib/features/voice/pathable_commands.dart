import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/format/travel_format.dart';
import '../../routing/route_progress.dart';
import '../../routing/routing_models.dart';
import 'hey_pathable.dart';

/// Runs one understood request and returns the sentence to show.
///
/// Spoken playback depends on the Audio setting inside [VoiceService.speak].
Future<String> answerPathableRequest(
  WidgetRef ref,
  BuildContext context,
  HeardRequest request,
) async {
  switch (request.intent) {
    case PathableIntent.followUp:
      return 'What do you need?';
    case PathableIntent.help:
      return 'Say take me to, and a place. You can also ask where you are, '
          'how much farther, or to report a hazard.';
    case PathableIntent.whereAmI:
      return _whereAmI(ref);
    case PathableIntent.farther:
    case PathableIntent.repeat:
      return _tripStatus(ref);
    case PathableIntent.report:
      if (context.mounted) context.push(AppRoutes.report);
      return 'Opening the hazard report.';
    case PathableIntent.stop:
      ref.read(activeRouteProvider.notifier).clear();
      if (context.mounted) context.go(AppRoutes.map);
      return 'Navigation stopped.';
    case PathableIntent.navigate:
      return _navigate(ref, context, request.place ?? '');
    case PathableIntent.unknown:
      return 'Say take me to, and a place name.';
  }
}

Future<String> _whereAmI(WidgetRef ref) async {
  final gps = ref.read(userLocationProvider).value;
  if (gps == null) {
    return 'I do not have a GPS fix yet.';
  }
  try {
    final matches = await ref.read(geocodingServiceProvider).search(
          '${gps.longitude},${gps.latitude}',
        );
    final name = matches.isEmpty ? null : matches.first.name.trim();
    if (name != null && name.isNotEmpty) {
      return 'You are near $name.';
    }
  } catch (_) {}
  return 'I have your GPS position, but not a street name yet.';
}

String _tripStatus(WidgetRef ref) {
  final route = ref.read(activeRouteProvider);
  final destination = ref.read(selectedDestinationProvider);
  if (route == null || destination == null) {
    return 'You are not on a trip. Say take me to, and a place.';
  }
  final user = ref.read(userLocationProvider).value;
  final progress = user == null
      ? null
      : routeProgress(
          geometry: route.geometry,
          maneuvers: route.maneuvers,
          user: user,
        );
  final index = progress?.maneuverIndex ?? 0;
  final instruction = route.maneuvers.isEmpty
      ? 'Continue on the path.'
      : route.maneuvers[index.clamp(0, route.maneuvers.length - 1)].instruction;
  final left = progress?.remainingMeters ?? route.distanceMeters;
  return '$instruction. ${TravelFormat.distance(left)} left to ${destination.name}.';
}

Future<String> _navigate(
  WidgetRef ref,
  BuildContext context,
  String place,
) async {
  final query = place.trim();
  if (query.isEmpty) return 'Where do you want to go?';

  try {
    final matches = await ref.read(geocodingServiceProvider).search(query);
    if (matches.isEmpty) {
      return 'I could not find $query.';
    }
    final destination = matches.first;
    var origin = ref.read(userLocationProvider).value;
    origin ??=
        (await ref.read(locationServiceProvider).getCurrentSample()).point;
    final profile = ref.read(accessibilityProfileProvider);
    final mode = profile.preferences.cyclistMode
        ? TravelMode.cycling
        : TravelMode.pedestrian;
    final result = await ref.read(routingServiceProvider).planRoute(
          RoutingRequest(
            origin: origin,
            destination: destination.location,
            mode: mode,
            preferences: profile.preferences,
          ),
        );
    if (result.routes.isEmpty) {
      return 'I could not find a walking path to ${destination.name}.';
    }
    var route = result.routes.first;
    for (final candidate in result.routes) {
      if (!candidate.excluded) {
        route = candidate;
        break;
      }
    }
    if (route.excluded) {
      return 'I could not find a walking path to ${destination.name}.';
    }
    ref.read(selectedDestinationProvider.notifier).select(destination);
    ref.read(activeRouteProvider.notifier).setRoute(route);
    ref.read(activeTravelModeProvider.notifier).setMode(mode);
    if (context.mounted) context.push(AppRoutes.navigation);
    final first = route.maneuvers.isEmpty
        ? 'Follow the path.'
        : route.maneuvers.first.instruction;
    return 'Starting directions to ${destination.name}. $first';
  } catch (error) {
    return 'I could not start directions. $error';
  }
}
