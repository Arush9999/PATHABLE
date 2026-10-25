import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/errors/app_failure.dart';
import '../../core/format/travel_format.dart';
import '../../core/location/device_heading.dart';
import '../../core/location/location_service.dart';
import '../../core/widgets/demo_banner.dart';
import '../../data/models/geo_point.dart';
import '../../data/models/hazard.dart';
import '../../routing/reroute_gate.dart';
import '../../routing/route_progress.dart';
import '../../routing/routing_models.dart';
import '../voice/blind_assist_screen.dart';
import 'widgets/route_map_view.dart';

class ActiveNavigationScreen extends ConsumerStatefulWidget {
  const ActiveNavigationScreen({super.key});

  @override
  ConsumerState<ActiveNavigationScreen> createState() =>
      _ActiveNavigationScreenState();
}

class _ActiveNavigationScreenState
    extends ConsumerState<ActiveNavigationScreen> {
  int _maneuverIndex = 0;
  int _spokenManeuver = -1;
  bool _followUser = true;
  bool _spokeArrival = false;
  GeoPoint? _user;
  RouteProgress _progress = RouteProgress.empty;
  String? _gpsMessage;
  StreamSubscription<GpsSample>? _gpsSub;
  final Set<String> _spokenHazards = {};
  final _rerouteGate = RerouteGate();
  DateTime? _rerouteNoticeUntil;

  bool get _audioOn =>
      ref.read(accessibilityProfileProvider).preferences.spokenInstructions;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_audioOn) {
        _speakManeuver(0, includeHazards: true);
      }
      _startGps();
    });
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    ref.read(voiceServiceProvider).stop();
    super.dispose();
  }

  Future<void> _startGps() async {
    final service = ref.read(locationServiceProvider);
    try {
      final sample = await service.getCurrentSample();
      if (!mounted) return;
      _applySample(sample);
      _gpsSub = service.watchSamples().listen(
        _applySample,
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _gpsMessage = error is AppFailure
                ? error.message
                : 'GPS updates stopped. $error';
          });
        },
      );
    } on AppFailure catch (error) {
      if (!mounted) return;
      setState(() => _gpsMessage = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _gpsMessage = 'GPS is unavailable. $error');
    }
  }

  void _applySample(GpsSample sample) {
    ref.read(gpsCourseProvider.notifier).publish(sample.courseDegrees);
    _applyFix(sample.point);
  }

  void _applyFix(GeoPoint point) {
    final route = ref.read(activeRouteProvider);
    if (!mounted || route == null) return;
    ref.read(userLocationProvider.notifier).publish(point);
    final progress = routeProgress(
      geometry: route.geometry,
      maneuvers: route.maneuvers,
      user: point,
    );
    final indexChanged = progress.maneuverIndex != _maneuverIndex;
    final now = DateTime.now();
    final showUpdate = _rerouteNoticeUntil != null &&
        now.isBefore(_rerouteNoticeUntil!);
    setState(() {
      _user = point;
      _progress = progress;
      _maneuverIndex = progress.maneuverIndex;
      if (progress.offRoute) {
        _gpsMessage =
            'You are off the planned path. The dotted line is still the plan.';
      } else if (showUpdate) {
        _gpsMessage = 'Route updated from your location.';
      } else {
        _gpsMessage = null;
        _rerouteNoticeUntil = null;
      }
    });

    if (_rerouteGate.shouldRequest(offRoute: progress.offRoute, now: now)) {
      _rerouteGate.markStarted(now);
      unawaited(_rerouteFrom(point));
    }

    if (_audioOn && !progress.offRoute && indexChanged) {
      _speakManeuver(progress.maneuverIndex, includeHazards: true);
    } else if (_audioOn && !progress.offRoute) {
      _speakUpcomingHazards(route, progress);
    }

    if (_audioOn &&
        !progress.offRoute &&
        progress.remainingMeters < 25 &&
        !_spokeArrival) {
      _spokeArrival = true;
      ref.read(voiceServiceProvider).speak('You are arriving at your destination.');
    }
  }

  /// Builds a replacement path from the live GPS fix.
  ///
  /// A failure leaves the current path in place.
  Future<void> _rerouteFrom(GeoPoint point) async {
    try {
      if (!mounted || !point.isValid) return;
      final destination = ref.read(selectedDestinationProvider);
      if (destination == null) return;
      final mode = ref.read(activeTravelModeProvider);
      final profile = ref.read(accessibilityProfileProvider);
      final routing = ref.read(routingServiceProvider);
      final voice = ref.read(voiceServiceProvider);
      final result = await routing.planRoute(
        RoutingRequest(
          origin: point,
          destination: destination.location,
          mode: mode,
          preferences: profile.preferences.copyWith(
            cyclistMode: mode == TravelMode.cycling,
          ),
          alternatives: 1,
        ),
      );
      if (!mounted) return;
      ScoredRoute? next;
      for (final route in result.routes) {
        if (!route.excluded) {
          next = route;
          break;
        }
      }
      next ??= result.routes.isEmpty ? null : result.routes.first;
      if (next == null) return;

      final progress = routeProgress(
        geometry: next.geometry,
        maneuvers: next.maneuvers,
        user: point,
      );
      ref.read(activeRouteProvider.notifier).setRoute(next);
      _spokenHazards.clear();
      setState(() {
        _user = point;
        _progress = progress;
        _maneuverIndex = progress.maneuverIndex;
        _spokenManeuver = progress.maneuverIndex;
        _spokeArrival = false;
        _gpsMessage = 'Route updated from your location.';
        _rerouteNoticeUntil = DateTime.now().add(const Duration(seconds: 8));
      });
      if (_audioOn && mounted) {
        await voice.speak('Route updated from your location.');
      }
    } catch (error) {
      debugPrint('Reroute kept the previous path: $error');
    } finally {
      _rerouteGate.markFinished();
    }
  }

  Future<void> _speakManeuver(int index, {required bool includeHazards}) async {
    final route = ref.read(activeRouteProvider);
    if (route == null || !_audioOn) return;
    if (_spokenManeuver == index && index != 0) return;
    _spokenManeuver = index;

    final voice = ref.read(voiceServiceProvider);
    final maneuver = route.maneuvers.isEmpty
        ? 'Route started. Follow the dotted path.'
        : route.maneuvers[index.clamp(0, route.maneuvers.length - 1)]
            .instruction;
    await voice.speak(maneuver);
    if (includeHazards) {
      _speakUpcomingHazards(route, _progress);
    }
    final profile = ref.read(accessibilityProfileProvider);
    if (profile.hapticAlerts) {
      await voice.hapticCue();
    }
  }

  Future<void> _speakUpcomingHazards(ScoredRoute route, RouteProgress progress) async {
    if (!_audioOn) return;
    final profile = ref.read(accessibilityProfileProvider);
    final voice = ref.read(voiceServiceProvider);
    final window = profile.warningDistanceMeters + 30;
    for (final hit in route.hazardHits) {
      final ahead = hit.distanceAlongRouteMeters - progress.alongMeters;
      if (ahead < -15 || ahead > window) continue;
      if (!_spokenHazards.add(hit.hazard.id)) continue;
      final certainty = hit.hazard.status == HazardStatus.active
          ? 'Confirmed'
          : 'Reported';
      await voice.speak(
        '$certainty ${hit.hazard.category.shortLabel.toLowerCase()} ahead. '
        'Status: ${hit.hazard.status.label}.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = ref.watch(activeRouteProvider);
    final mode = ref.watch(activeTravelModeProvider);
    final config = ref.watch(appConfigurationProvider);
    final destination = ref.watch(selectedDestinationProvider);
    final profile = ref.watch(accessibilityProfileProvider);
    final audioOn = profile.preferences.spokenInstructions;
    final blind = profile.preferences.blindMode;
    final heading = displayHeadingDegrees(
      gpsCourse: ref.watch(gpsCourseProvider),
      compassDegrees: ref.watch(compassHeadingProvider).asData?.value,
    );
    final theme = Theme.of(context);

    if (route == null || destination == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Navigation')),
        body: Center(
          child: FilledButton(
            onPressed: () => context.go(AppRoutes.map),
            child: const Text('Return to map'),
          ),
        ),
      );
    }

    final origin = route.geometry.isNotEmpty
        ? route.geometry.first
        : routingOriginFor(
            selectedOrigin: ref.watch(selectedOriginProvider),
            gps: _user ?? ref.watch(userLocationProvider).value,
          );
    final maneuver = route.maneuvers.isEmpty
        ? null
        : route.maneuvers[_maneuverIndex.clamp(0, route.maneuvers.length - 1)];
    final remaining = _user == null
        ? route.distanceMeters
        : _progress.remainingMeters;
    final stepDistance = _user == null
        ? maneuver?.distanceMeters
        : _progress.maneuverRemainingMeters;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          mode == TravelMode.cycling ? 'Bike navigation' : 'Walk navigation',
        ),
        actions: [
          IconButton(
            tooltip: audioOn ? 'Turn audio off' : 'Turn audio on',
            onPressed: () {
              ref.read(accessibilityProfileProvider.notifier).updatePreferences(
                    profile.preferences.copyWith(spokenInstructions: !audioOn),
                  );
              if (audioOn) {
                ref.read(voiceServiceProvider).stopSpeaking();
              }
            },
            icon: Icon(audioOn ? Icons.volume_up : Icons.volume_off),
          ),
          TextButton(
            onPressed: () {
              ref.read(voiceServiceProvider).stop();
              ref.read(activeRouteProvider.notifier).clear();
              context.go(AppRoutes.map);
            },
            child: const Text('End'),
          ),
        ],
      ),
      body: blind
          ? HeyPathableMic(
              headline: [
                maneuver?.instruction ?? 'Follow the path.',
                stepDistance == null
                    ? TravelFormat.summaryLine(remaining, route.durationSeconds)
                    : '${TravelFormat.distance(stepDistance)} for this step'
                        ' · ${TravelFormat.distance(remaining)} left',
              ].join('\n'),
            )
          : Column(
        children: [
          if (config.isDemoMode || route.isDemonstration)
            const DemoBanner(
              message:
                  'Demonstration navigation. Directions are not verified real-world guidance.',
            ),
          Expanded(
            child: Stack(
              children: [
                RouteMapView(
                  styleUrl: config.mapStyleUrl,
                  origin: origin,
                  destination: destination.location,
                  routes: [route],
                  selectedRouteId: route.id,
                  hazards: route.hazardHits.map((h) => h.hazard).toList(),
                  userLocation: _user,
                  headingDegrees: heading,
                  followUser: _followUser && _user != null,
                  onFollowDismissed: () {
                    if (!_followUser) return;
                    setState(() => _followUser = false);
                  },
                ),
                Positioned(
                  right: 12,
                  bottom: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'nav-recenter',
                    tooltip: 'Re-center on GPS',
                    onPressed: () => setState(() => _followUser = true),
                    child: Icon(
                      _followUser && _user != null
                          ? Icons.navigation
                          : Icons.my_location,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Material(
            elevation: 10,
            color: theme.colorScheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          foregroundColor: theme.colorScheme.primary,
                          child: Icon(
                            mode == TravelMode.cycling
                                ? Icons.directions_bike
                                : Icons.directions_walk,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            maneuver?.instruction ??
                                'Follow the dotted path.',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      stepDistance == null
                          ? TravelFormat.summaryLine(
                              remaining,
                              route.durationSeconds,
                            )
                          : '${TravelFormat.distance(stepDistance)} for this step'
                              ' · ${TravelFormat.distance(remaining)} left',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_user == null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _gpsMessage ??
                            'Waiting for a GPS fix. The route is planned, but your position is not being followed yet.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ] else if (_gpsMessage != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _gpsMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _gpsMessage!.startsWith('Route updated')
                              ? theme.colorScheme.primary
                              : theme.colorScheme.error,
                        ),
                      ),
                    ],
                    if (route.hazardHits.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${route.hazardHits.length} hazard notice(s) on this corridor',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                    if (_user == null) ...[
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () {
                          if (_maneuverIndex < route.maneuvers.length - 1) {
                            setState(() => _maneuverIndex++);
                            _speakManeuver(
                              _maneuverIndex,
                              includeHazards: true,
                            );
                          }
                        },
                        child: const Text('Next instruction'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
