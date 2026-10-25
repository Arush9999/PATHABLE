import 'dart:math' show Point, max, min;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/geo/dashed_polyline.dart';
import '../../../core/geo/geo_math.dart';
import '../../../data/models/geo_point.dart';
import '../../../data/models/hazard.dart';
import '../../../routing/routing_models.dart';
import '../../map/user_location_arrow.dart';

/// MapLibre map that draws the planned path as a dotted line.
///
/// `LineOptions` has no dash array, so the geometry is sampled into short
/// segments with gaps.
class RouteMapView extends StatefulWidget {
  const RouteMapView({
    super.key,
    required this.styleUrl,
    required this.origin,
    required this.destination,
    required this.routes,
    this.selectedRouteId,
    this.hazards = const [],
    this.userLocation,
    this.headingDegrees = 0,
    this.followUser = false,
    this.onRouteSelected,
    this.onFollowDismissed,
  });

  final String styleUrl;
  final GeoPoint origin;
  final GeoPoint destination;
  final List<ScoredRoute> routes;
  final String? selectedRouteId;
  final List<Hazard> hazards;
  final GeoPoint? userLocation;

  /// Clockwise degrees from north. `0` points the arrow north.
  final double headingDegrees;
  final bool followUser;
  final ValueChanged<ScoredRoute>? onRouteSelected;
  final VoidCallback? onFollowDismissed;

  @override
  State<RouteMapView> createState() => _RouteMapViewState();
}

class _RouteMapViewState extends State<RouteMapView> {
  MapLibreMapController? _controller;
  bool _styleReady = false;
  bool _movingCamera = false;
  int _cameraToken = 0;
  final List<Line> _lines = [];
  final List<Circle> _circles = [];
  final List<Symbol> _symbols = [];
  final _arrow = UserLocationArrow();

  @override
  void didUpdateWidget(covariant RouteMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_styleReady) return;

    final routeChanged = oldWidget.selectedRouteId != widget.selectedRouteId ||
        !_sameRoutes(oldWidget.routes, widget.routes) ||
        oldWidget.origin != widget.origin ||
        oldWidget.destination != widget.destination ||
        !_sameHazards(oldWidget.hazards, widget.hazards);
    final userChanged = oldWidget.userLocation != widget.userLocation;
    final headingChanged = oldWidget.headingDegrees != widget.headingDegrees;

    if (routeChanged) {
      _redraw(fitRoute: !widget.followUser);
    } else if (userChanged || headingChanged) {
      _syncArrow();
      if (userChanged && widget.followUser) _frameUser();
    }

    if (!oldWidget.followUser && widget.followUser && widget.userLocation != null) {
      _frameUser();
    }
  }

  bool _sameRoutes(List<ScoredRoute> a, List<ScoredRoute> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].geometry.length != b[i].geometry.length) {
        return false;
      }
      final aGeometry = a[i].geometry;
      final bGeometry = b[i].geometry;
      if (aGeometry.isNotEmpty &&
          bGeometry.isNotEmpty &&
          (aGeometry.first != bGeometry.first ||
              aGeometry.last != bGeometry.last)) {
        return false;
      }
    }
    return true;
  }

  bool _sameHazards(List<Hazard> a, List<Hazard> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  Future<void> _redraw({bool fitRoute = true}) async {
    final controller = _controller;
    if (controller == null || !_styleReady) return;

    if (_lines.isNotEmpty) {
      await controller.removeLines(_lines);
      _lines.clear();
    }
    if (_circles.isNotEmpty) {
      await controller.removeCircles(_circles);
      _circles.clear();
    }
    if (_symbols.isNotEmpty) {
      await controller.removeSymbols(_symbols);
      _symbols.clear();
    }

    final selectedId = widget.selectedRouteId;
    final ordered = [
      ...widget.routes.where((r) => r.id != selectedId),
      ...widget.routes.where((r) => r.id == selectedId),
    ];

    final haloOptions = <LineOptions>[];
    final haloData = <Map<String, dynamic>>[];
    final dashOptions = <LineOptions>[];
    final dashData = <Map<String, dynamic>>[];

    for (final route in ordered) {
      if (route.geometry.length < 2) continue;
      final selected = route.id == selectedId;
      final color = !selected
          ? '#94A3B8'
          : (route.excluded ? '#DC2626' : '#047857');
      final dashes = dashedPolyline(route.geometry);
      final data = {'routeId': route.id};
      for (final dash in dashes) {
        final geometry =
            dash.map((p) => LatLng(p.latitude, p.longitude)).toList();
        haloOptions.add(
          LineOptions(
            geometry: geometry,
            lineColor: '#FFFFFF',
            lineWidth: selected ? 7 : 5,
            lineOpacity: selected ? 0.95 : 0.7,
            lineJoin: 'round',
          ),
        );
        haloData.add(data);
        dashOptions.add(
          LineOptions(
            geometry: geometry,
            lineColor: color,
            lineWidth: selected ? 4.2 : 2.6,
            lineOpacity: selected ? 1 : 0.8,
            lineJoin: 'round',
          ),
        );
        dashData.add(data);
      }
    }

    if (haloOptions.isNotEmpty) {
      _lines.addAll(await controller.addLines(haloOptions, haloData));
    }
    if (dashOptions.isNotEmpty) {
      _lines.addAll(await controller.addLines(dashOptions, dashData));
    }

    _circles.addAll(
      await controller.addCircles([
        CircleOptions(
          geometry: LatLng(widget.origin.latitude, widget.origin.longitude),
          circleRadius: 7,
          circleColor: '#059669',
          circleStrokeWidth: 3,
          circleStrokeColor: '#FFFFFF',
        ),
        CircleOptions(
          geometry: LatLng(
            widget.destination.latitude,
            widget.destination.longitude,
          ),
          circleRadius: 7,
          circleColor: '#DC2626',
          circleStrokeWidth: 3,
          circleStrokeColor: '#FFFFFF',
        ),
        for (final hazard in widget.hazards.take(24))
          CircleOptions(
            geometry: LatLng(
              hazard.location.latitude,
              hazard.location.longitude,
            ),
            circleRadius: 6,
            circleColor: '#F59E0B',
            circleStrokeWidth: 2,
            circleStrokeColor: '#FFFFFF',
          ),
      ]),
    );

    _symbols.addAll(
      await controller.addSymbols([
        SymbolOptions(
          geometry: LatLng(widget.origin.latitude, widget.origin.longitude),
          textField: 'Start',
          textOffset: const Offset(0, 1.4),
          textSize: 12,
          textColor: '#065F46',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 1.2,
        ),
        SymbolOptions(
          geometry: LatLng(
            widget.destination.latitude,
            widget.destination.longitude,
          ),
          textField: 'End',
          textOffset: const Offset(0, 1.4),
          textSize: 12,
          textColor: '#991B1B',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 1.2,
        ),
      ]),
    );

    await _syncArrow();
    if (widget.followUser && widget.userLocation != null) {
      await _frameUser();
    } else if (fitRoute) {
      await _fitBounds(controller);
    }
  }

  Future<void> _syncArrow() {
    final controller = _controller;
    if (controller == null || !_styleReady) return Future<void>.value();
    return _arrow.sync(
      controller,
      point: widget.userLocation,
      headingDegrees: widget.headingDegrees,
    );
  }

  Future<void> _frameUser() async {
    final controller = _controller;
    final user = widget.userLocation;
    if (controller == null || user == null) return;
    final token = ++_cameraToken;
    _movingCamera = true;
    try {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(user.latitude, user.longitude),
            zoom: 16.4,
          ),
        ),
      );
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (token == _cameraToken) _movingCamera = false;
    }
  }

  Future<void> _fitBounds(MapLibreMapController controller) async {
    final points = <GeoPoint>[widget.origin, widget.destination];
    final selected = widget.routes
        .where((r) => r.id == widget.selectedRouteId)
        .firstOrNull;
    if (selected != null) {
      points.addAll(selected.geometry);
    } else {
      for (final route in widget.routes) {
        points.addAll(route.geometry);
      }
    }
    if (points.isEmpty) return;

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points) {
      minLat = min(minLat, p.latitude);
      maxLat = max(maxLat, p.latitude);
      minLng = min(minLng, p.longitude);
      maxLng = max(maxLng, p.longitude);
    }

    if ((maxLat - minLat).abs() < 0.001) {
      minLat -= 0.002;
      maxLat += 0.002;
    }
    if ((maxLng - minLng).abs() < 0.001) {
      minLng -= 0.002;
      maxLng += 0.002;
    }

    final token = ++_cameraToken;
    _movingCamera = true;
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          left: 36,
          top: 36,
          right: 36,
          bottom: 36,
        ),
      );
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (token == _cameraToken) _movingCamera = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      styleString: widget.styleUrl,
      initialCameraPosition: CameraPosition(
        target: LatLng(widget.origin.latitude, widget.origin.longitude),
        zoom: 14,
      ),
      compassEnabled: true,
      rotateGesturesEnabled: true,
      scrollGesturesEnabled: true,
      zoomGesturesEnabled: true,
      attributionButtonMargins: const Point(8, 8),
      logoViewMargins: const Point(8, 28),
      onMapCreated: (controller) {
        _controller = controller;
        controller.onLineTapped.add((line) {
          final id = line.data?['routeId'] as String?;
          if (id == null || widget.onRouteSelected == null) return;
          final match = widget.routes.where((r) => r.id == id).firstOrNull;
          if (match != null) widget.onRouteSelected!(match);
        });
      },
      onCameraMove: (position) {
        if (_movingCamera || !widget.followUser) return;
        final user = widget.userLocation;
        if (user == null) {
          widget.onFollowDismissed?.call();
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
        widget.onFollowDismissed?.call();
      },
      onStyleLoadedCallback: () async {
        _styleReady = true;
        _arrow.reset();
        await _redraw(fitRoute: !widget.followUser);
      },
    );
  }
}
