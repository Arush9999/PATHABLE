import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/errors/app_failure.dart';
import '../../core/geo/geo_math.dart';
import '../../core/location/device_heading.dart';
import '../../core/location/location_service.dart';
import '../../core/widgets/demo_banner.dart';
import '../../data/local/demo_data.dart';
import '../../data/models/geo_point.dart';
import '../../data/models/hazard.dart';
import '../voice/blind_assist_screen.dart';
import 'user_location_arrow.dart';
import 'widgets/hazard_list_sheet.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MapLibreMapController? _controller;
  bool _annotationsReady = false;
  bool _tapHandlersAttached = false;
  bool _styleReady = false;
  bool _gesturesArmed = false;
  bool _followGps = true;
  bool _movingCamera = false;
  bool _didFollowZoom = false;
  bool _forceNextZoom = false;
  int _cameraToken = 0;
  int _gpsGeneration = 0;
  String? _locationMessage;
  StreamSubscription<GpsSample>? _gpsSub;
  final _arrow = UserLocationArrow();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startGps());
    });
  }

  @override
  void activate() {
    super.activate();
    unawaited(_startGps());
  }

  @override
  void deactivate() {
    _gpsGeneration++;
    unawaited(_gpsSub?.cancel());
    _gpsSub = null;
    super.deactivate();
  }

  @override
  void dispose() {
    _gpsGeneration++;
    unawaited(_gpsSub?.cancel());
    super.dispose();
  }

  Future<void> _startGps() async {
    final generation = ++_gpsGeneration;
    await _gpsSub?.cancel();
    _gpsSub = null;
    final service = ref.read(locationServiceProvider);
    try {
      final sample = await service.getCurrentSample();
      if (!mounted || generation != _gpsGeneration) return;
      _publishSample(sample);
      final sub = service.watchSamples(distanceFilterMeters: 4).listen(
        _publishSample,
        onError: (Object error) {
          if (!mounted || generation != _gpsGeneration) return;
          setState(() {
            _locationMessage = error is AppFailure
                ? error.message
                : 'GPS updates stopped. $error';
          });
        },
      );
      if (!mounted || generation != _gpsGeneration) {
        await sub.cancel();
        return;
      }
      _gpsSub = sub;
    } on AppFailure catch (error) {
      if (!mounted || generation != _gpsGeneration) return;
      setState(() => _locationMessage = error.message);
    } catch (error) {
      if (!mounted || generation != _gpsGeneration) return;
      setState(() => _locationMessage = 'Location could not be read. $error');
    }
  }

  void _publishSample(GpsSample sample) {
    ref.read(gpsCourseProvider.notifier).publish(sample.courseDegrees);
    ref.read(userLocationProvider.notifier).publish(sample.point);
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(accessibilityProfileProvider).preferences.blindMode) {
      return const BlindAssistScreen();
    }

    final config = ref.watch(appConfigurationProvider);
    final center = ref.watch(mapCenterProvider);
    final hazardsAsync = ref.watch(nearbyHazardsProvider);
    final userLocation = ref.watch(userLocationProvider);
    final locationNotice = ref.watch(locationNoticeProvider);
    final locationBanner = locationNotice ??
        (userLocation.isLoading
            ? 'PathAble is requesting location permission and a GPS fix so directions can start from where you are.'
            : null);

    ref.listen(nearbyHazardsProvider, (previous, next) {
      next.whenData(_syncHazardAnnotations);
    });
    ref.listen(userLocationProvider, (previous, next) {
      final point = next.asData?.value ??
          (next.isLoading ? previous?.asData?.value : null);
      unawaited(_onUserLocation(point));
    });
    ref.listen(gpsCourseProvider, (_, _) {
      unawaited(_syncArrow(ref.read(userLocationProvider).asData?.value));
    });
    ref.listen(compassHeadingProvider, (_, _) {
      unawaited(_syncArrow(ref.read(userLocationProvider).asData?.value));
    });

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
      body: Column(
        children: [
          if (config.isDemoMode) const DemoBanner(),
          Expanded(
            child: Stack(
              children: [
                MapLibreMap(
                  styleString: config.mapStyleUrl,
                  initialCameraPosition: CameraPosition(
                    target: LatLng(center.latitude, center.longitude),
                    zoom: 15,
                  ),
                  trackCameraPosition: true,
                  compassEnabled: true,
                  attributionButtonMargins: const Point(8, 8),
                  logoViewMargins: const Point(8, 32),
                  onMapCreated: (controller) async {
                    _controller = controller;
                    _attachTapHandlers(controller);
                    await _syncHazardAnnotations(
                      hazardsAsync.value ?? const [],
                    );
                  },
                  onCameraMove: _onCameraMove,
                  onStyleLoadedCallback: () async {
                    _styleReady = true;
                    _arrow.reset();
                    await _syncHazardAnnotations(
                      hazardsAsync.value ?? const [],
                    );
                    final point = ref.read(userLocationProvider).asData?.value;
                    await _syncArrow(point);
                    if (_followGps && point != null) {
                      await _frameUser(point, forceZoom: !_didFollowZoom);
                      _didFollowZoom = true;
                    }
                    await Future<void>.delayed(const Duration(milliseconds: 500));
                    _gesturesArmed = true;
                  },
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  top: 8,
                  child: Material(
                    type: MaterialType.transparency,
                    child: const _SearchAndProfileBar(),
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 72,
                  child: Column(
                    children: [
                      Semantics(
                        button: true,
                        label: _followGps && userLocation.value != null
                            ? 'Following your location'
                            : 'Recenter on my location',
                        child: FloatingActionButton.small(
                          heroTag: 'recenter',
                          tooltip: _followGps && userLocation.value != null
                              ? 'Following your location'
                              : 'Recenter on my location',
                          onPressed: _recenter,
                          child: Icon(
                            _followGps && userLocation.value != null
                                ? Icons.navigation
                                : Icons.my_location,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Semantics(
                        button: true,
                        label: 'Show nearby hazards as a list',
                        child: FloatingActionButton.small(
                          heroTag: 'hazardList',
                          tooltip: 'Hazard list',
                          onPressed: () => _showHazardSheet(
                            hazardsAsync.value ?? const [],
                          ),
                          child: const Icon(Icons.list_alt),
                        ),
                      ),
                    ],
                  ),
                ),
                if (locationBanner != null || _locationMessage != null)
                  Positioned(
                    left: 8,
                    right: 64,
                    bottom: 12,
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(12),
                      color: Theme.of(context).colorScheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Text(
                          _locationMessage ?? locationBanner!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _MapFooter(
            hazardCount: hazardsAsync.value?.length ?? 0,
            hasGps: userLocation.value != null,
          ),
        ],
      ),
      floatingActionButton: Semantics(
        button: true,
        label: 'Report a hazard',
        child: FloatingActionButton.extended(
          onPressed: () => context.push(AppRoutes.report),
          icon: const Icon(Icons.add_alert),
          label: const Text('Report'),
        ),
      ),
    );
  }

  void _attachTapHandlers(MapLibreMapController controller) {
    if (_tapHandlersAttached) return;
    _tapHandlersAttached = true;

    void openHazard(Map<String, dynamic>? data) {
      final id = data?['hazardId'] as String?;
      if (id == null || !mounted) return;
      ref.read(selectedHazardIdProvider.notifier).select(id);
      context.push(AppRoutes.hazard(id));
    }

    controller.onCircleTapped.add((circle) => openHazard(circle.data));
    controller.onSymbolTapped.add((symbol) => openHazard(symbol.data));
  }

  Future<void> _recenter() async {
    setState(() {
      _followGps = true;
      _forceNextZoom = true;
      _locationMessage = 'Requesting location…';
    });
    try {
      final sample =
          await ref.read(locationServiceProvider).getCurrentSample();
      if (!mounted) return;
      final previous = ref.read(userLocationProvider).asData?.value;
      _publishSample(sample);
      setState(() => _locationMessage = null);
      if (previous == sample.point) {
        _forceNextZoom = false;
        _didFollowZoom = true;
        await _frameUser(sample.point, forceZoom: true);
      }
    } on AppFailure catch (error) {
      if (!mounted) return;
      setState(() => _locationMessage = error.message);
      await _frameUser(DemoData.startLocation, forceZoom: true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _locationMessage = 'Location could not be read. $error');
      await _frameUser(DemoData.startLocation, forceZoom: true);
    }
  }

  void _onCameraMove(CameraPosition position) {
    if (!_gesturesArmed || _movingCamera || !_followGps) return;
    final user = ref.read(userLocationProvider).asData?.value;
    if (user == null) {
      setState(() => _followGps = false);
      return;
    }
    final moved = distanceMeters(
      user,
      GeoPoint(
        latitude: position.target.latitude,
        longitude: position.target.longitude,
      ),
    );
    if (moved < 30) return;
    setState(() => _followGps = false);
  }

  Future<void> _onUserLocation(GeoPoint? point) async {
    await _syncArrow(point);
    if (!_followGps || point == null) return;
    final zoom = _forceNextZoom || !_didFollowZoom;
    _forceNextZoom = false;
    if (zoom) _didFollowZoom = true;
    await _frameUser(point, forceZoom: zoom);
  }

  double _headingDegrees() {
    return displayHeadingDegrees(
      gpsCourse: ref.read(gpsCourseProvider),
      compassDegrees: ref.read(compassHeadingProvider).asData?.value,
    );
  }

  Future<void> _syncArrow(GeoPoint? point) {
    final controller = _controller;
    if (controller == null || !_styleReady) return Future<void>.value();
    return _arrow.sync(
      controller,
      point: point,
      headingDegrees: _headingDegrees(),
    );
  }

  Future<void> _frameUser(GeoPoint point, {required bool forceZoom}) async {
    final controller = _controller;
    if (controller == null) return;
    final token = ++_cameraToken;
    _movingCamera = true;
    try {
      if (forceZoom) {
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(point.latitude, point.longitude),
              zoom: 16,
            ),
          ),
        );
      } else {
        await controller.animateCamera(
          CameraUpdate.newLatLng(LatLng(point.latitude, point.longitude)),
        );
      }
    } catch (error) {
      debugPrint('Camera follow deferred: $error');
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (token == _cameraToken) _movingCamera = false;
    }
  }

  Future<void> _syncHazardAnnotations(List<Hazard> hazards) async {
    final controller = _controller;
    if (controller == null) return;

    try {
      if (_annotationsReady) {
        await controller.clearCircles();
        await controller.clearSymbols();
      }

      for (final hazard in hazards) {
        if (hazard.status == HazardStatus.resolved) continue;
        final geometry = LatLng(
          hazard.location.latitude,
          hazard.location.longitude,
        );
        final data = <String, dynamic>{
          'hazardId': hazard.id,
          'status': hazard.status.name,
          'demo': hazard.isDemonstration.toString(),
        };

        await controller.addCircle(
          CircleOptions(
            geometry: geometry,
            circleRadius: 10,
            circleColor: _colorForStatus(hazard.status),
            circleStrokeWidth: 2,
            circleStrokeColor: '#111827',
            circleOpacity: 0.9,
          ),
          data,
        );

        await controller.addSymbol(
          SymbolOptions(
            geometry: geometry,
            textField: hazard.category.shortLabel,
            textOffset: const Offset(0, 1.6),
            textSize: 11,
            textColor: '#111827',
            textHaloColor: '#FFFFFF',
            textHaloWidth: 1.4,
          ),
          data,
        );
      }
      _annotationsReady = true;
    } catch (error) {
      // Style may not be ready yet; onStyleLoadedCallback retries.
      debugPrint('Hazard annotation sync deferred: $error');
    }
  }

  static String _colorForStatus(HazardStatus status) => switch (status) {
        HazardStatus.active => '#DC2626',
        HazardStatus.provisional => '#0EA5E9',
        HazardStatus.stale => '#64748B',
        HazardStatus.underReview => '#047857',
        HazardStatus.resolved => '#059669',
      };

  void _showHazardSheet(List<Hazard> hazards) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.45,
          minChildSize: 0.25,
          maxChildSize: 0.85,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: Row(
                    children: [
                      Text(
                        'Nearby hazards',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Spacer(),
                      Text('${hazards.length} shown'),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: HazardStatusLegend(),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: HazardListSheet(hazards: hazards),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _SearchAndProfileBar extends ConsumerWidget {
  const _SearchAndProfileBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Session stream (not only the signed-in flag) so the initial updates
    // when auth metadata changes while the user stays signed in.
    final session = ref.watch(authSessionProvider).asData?.value;
    final signedIn = session != null;
    final displayName = signedIn
        ? ref.watch(userProfileServiceProvider).displayName
        : null;
    return Row(
      children: [
        Expanded(
          child: Material(
            elevation: 3,
            shadowColor: theme.colorScheme.primary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
            color: theme.colorScheme.surface.withValues(alpha: 0.97),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Search for a destination',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => context.push(AppRoutes.search),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Icon(
                                  Icons.search,
                                  color: theme.colorScheme.primary,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Search destination',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Accessibility profile',
                    onPressed: () => context.push(AppRoutes.accessibility),
                    icon: Icon(
                      Icons.accessibility_new,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _AccountCircleButton(
          signedIn: signedIn,
          initial: _accountInitial(displayName),
        ),
      ],
    );
  }
}

/// First letter of a display name or email local-part, when one exists.
String? _accountInitial(String? displayName) {
  final source = displayName?.trim() ?? '';
  if (source.isEmpty) return null;
  return String.fromCharCode(source.runes.first).toUpperCase();
}

/// Round account control at the top-end of the map, in the style of the
/// Google account circle. Signed-in users see an initial when one is known.
class _AccountCircleButton extends StatelessWidget {
  const _AccountCircleButton({
    required this.signedIn,
    required this.initial,
  });

  final bool signedIn;
  final String? initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final showInitial = signedIn && initial != null;
    final background = signedIn ? scheme.primary : scheme.surface;
    final foreground = signedIn ? scheme.onPrimary : scheme.primary;

    return Tooltip(
      message: 'Account',
      child: Semantics(
        button: true,
        label: 'Account',
        child: Material(
          color: background,
          elevation: 3,
          shadowColor: scheme.primary.withValues(alpha: 0.22),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => context.push(AppRoutes.account),
            child: SizedBox(
              width: 48,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: signedIn
                      ? null
                      : Border.all(color: scheme.primary, width: 1.5),
                ),
                child: Center(
                  child: showInitial
                      ? Text(
                          initial!,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        )
                      : Icon(Icons.person, color: foreground, size: 26),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapFooter extends StatelessWidget {
  const _MapFooter({
    required this.hazardCount,
    required this.hasGps,
  });

  final int hazardCount;
  final bool hasGps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 6,
      shadowColor: theme.colorScheme.primary.withValues(alpha: 0.12),
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.secondary.withValues(alpha: 0.35),
                width: 2,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$hazardCount nearby reports · '
                '${hasGps ? 'GPS available' : 'GPS unavailable'} · '
                '© OpenStreetMap contributors',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
              const HazardStatusLegend(),
            ],
          ),
        ),
      ),
    );
  }
}
