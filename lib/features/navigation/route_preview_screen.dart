import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/geo/geo_math.dart';
import '../../core/format/travel_format.dart';
import '../../core/widgets/demo_banner.dart';
import '../../data/models/geo_point.dart';
import '../../data/models/hazard.dart';
import '../../routing/routing_models.dart';
import 'widgets/route_map_view.dart';

class RoutePreviewScreen extends ConsumerStatefulWidget {
  const RoutePreviewScreen({super.key});

  @override
  ConsumerState<RoutePreviewScreen> createState() => _RoutePreviewScreenState();
}

class _RoutePreviewScreenState extends ConsumerState<RoutePreviewScreen> {
  RoutingResult? _result;
  String? _error;
  bool _loading = true;
  ScoredRoute? _selected;
  TravelMode _mode = TravelMode.pedestrian;
  List<Hazard> _hazards = const [];
  GeoPoint? _origin;
  String _originLabel = 'Start';
  String? _originDetail;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(accessibilityProfileProvider);
    _mode = profile.preferences.cyclistMode
        ? TravelMode.cycling
        : TravelMode.pedestrian;
    _plan();
  }

  Future<void> _plan() async {
    final destination = ref.read(selectedDestinationProvider);
    if (destination == null) {
      setState(() {
        _loading = false;
        _error = 'Choose a destination first.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final selectedOrigin = ref.read(selectedOriginProvider);
      GeoPoint? gps = ref.read(userLocationProvider).value;
      String? gpsNote;
      if (!originIsChosenAddress(selectedOrigin)) {
        try {
          gps = await ref.read(locationServiceProvider).getCurrentPosition();
          ref.read(userLocationProvider.notifier).publish(gps);
        } catch (error) {
          if (gps == null) {
            final notice = ref.read(locationNoticeProvider);
            gpsNote = notice ??
                'GPS is unavailable, so the start is the demonstration pin. $error';
          }
        }
      }
      final origin = routingOriginFor(
        selectedOrigin: selectedOrigin,
        gps: gps,
      );
      final profile = ref.read(accessibilityProfileProvider);
      final preferences = profile.preferences.copyWith(
        cyclistMode: _mode == TravelMode.cycling,
      );

      final result = await ref.read(routingServiceProvider).planRoute(
            RoutingRequest(
              origin: origin,
              destination: destination.location,
              mode: _mode,
              preferences: preferences,
            ),
          );

      final hazards = await ref.read(hazardRepositoryProvider).getNearbyHazards(
            center: origin,
            radiusMeters: hazardSearchRadiusMeters(
              origin,
              destination.location,
            ),
          );

      if (!mounted) return;
      ScoredRoute? selected;
      for (final route in result.routes) {
        if (!route.excluded) {
          selected = route;
          break;
        }
      }
      selected ??= result.routes.isEmpty ? null : result.routes.first;
      setState(() {
        _origin = origin;
        _originLabel = routingOriginLabel(
          selectedOrigin: ref.read(selectedOriginProvider),
          gps: gps,
        );
        _originDetail = gpsNote ??
            routingOriginSubtitle(
              selectedOrigin: ref.read(selectedOriginProvider),
              gps: gps,
            );
        _result = result;
        _selected = selected;
        _hazards = hazards;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final destination = ref.watch(selectedDestinationProvider);
    final config = ref.watch(appConfigurationProvider);
    final theme = Theme.of(context);
    final origin = _origin;

    // Re-plan when the user changes start address from search.
    ref.listen(selectedOriginProvider, (previous, next) {
      if (previous?.id != next?.id && next != null && !_loading) {
        _plan();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(destination?.name ?? 'Route preview'),
        actions: [
          IconButton(
            tooltip: 'Refresh route',
            onPressed: _loading ? null : _plan,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (config.isDemoMode || (_result?.isDemonstration ?? false))
            const DemoBanner(
              message:
                  'Demonstration routing — not a verified real-world route.',
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
            child: Material(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(
                      Icons.my_location,
                      color: theme.colorScheme.secondary,
                    ),
                    title: Text(
                      _originLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      _originDetail ?? 'Tap to set a start address',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.edit, size: 16),
                    onTap: () async {
                      await context.push('${AppRoutes.search}?for=origin');
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(
                      Icons.flag,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      destination?.name ?? 'Destination',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.edit, size: 16),
                    onTap: () => context.push(AppRoutes.search),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: SegmentedButton<TravelMode>(
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(
                  value: TravelMode.pedestrian,
                  label: Text('Walk'),
                  icon: Icon(Icons.directions_walk),
                ),
                ButtonSegment(
                  value: TravelMode.cycling,
                  label: Text('Bike'),
                  icon: Icon(Icons.directions_bike),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _loading
                  ? null
                  : (value) {
                      setState(() => _mode = value.first);
                      _plan();
                    },
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else if (_result != null && origin != null && destination != null)
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    flex: 5,
                    child: RouteMapView(
                      styleUrl: config.mapStyleUrl,
                      origin: origin,
                      destination: destination.location,
                      routes: _result!.routes,
                      selectedRouteId: _selected?.id,
                      hazards: _hazards,
                      onRouteSelected: (route) {
                        setState(() => _selected = route);
                      },
                    ),
                  ),
                  if (_result!.limitations.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                      child: Text(
                        _result!.limitations.first,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  Expanded(
                    flex: 4,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                      children: [
                        ..._result!.routes.map((route) {
                          final selected = _selected?.id == route.id;
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 3,
                            ),
                            color: selected
                                ? theme.colorScheme.primaryContainer
                                : null,
                            child: ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              selected: selected,
                              leading: Icon(
                                _mode == TravelMode.cycling
                                    ? Icons.directions_bike
                                    : Icons.directions_walk,
                                color: selected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              title: Text(
                                route.label.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${TravelFormat.summaryLine(route.distanceMeters, route.durationSeconds)}\n'
                                '${route.hazardHits.length} hazard notice(s)'
                                '${route.excluded ? ' · Impassable barrier' : ''}',
                              ),
                              isThreeLine: true,
                              trailing: selected
                                  ? Icon(
                                      Icons.check_circle,
                                      color: theme.colorScheme.secondary,
                                    )
                                  : const Icon(Icons.chevron_right),
                              onTap: () => setState(() => _selected = route),
                            ),
                          );
                        }),
                        if (_selected != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Why this route',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ..._selected!.explanations.map(
                            (line) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('• $line'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: FilledButton.icon(
            onPressed: _selected == null || _selected!.excluded
                ? null
                : () {
                    ref
                        .read(activeRouteProvider.notifier)
                        .setRoute(_selected!);
                    ref.read(activeTravelModeProvider.notifier).setMode(_mode);
                    context.push(AppRoutes.navigation);
                  },
            icon: Icon(
              _mode == TravelMode.cycling
                  ? Icons.directions_bike
                  : Icons.navigation,
            ),
            label: Text(
              _selected == null
                  ? 'Start navigation'
                  : 'Start · ${TravelFormat.duration(_selected!.durationSeconds)} · '
                      'ETA ${TravelFormat.etaClock(_selected!.durationSeconds)}',
            ),
          ),
        ),
      ),
    );
  }
}
