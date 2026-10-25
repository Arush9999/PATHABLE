import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../data/models/geo_point.dart';
import '../errors/app_failure.dart';

/// One GPS reading. [courseDegrees] is set only when the platform reported a
/// bearing. A stationary fix leaves it null so the arrow can use the compass.
class GpsSample {
  const GpsSample({required this.point, this.courseDegrees});

  final GeoPoint point;
  final double? courseDegrees;
}

/// Location access with explicit permission and service checks.
class LocationService {
  const LocationService();

  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  /// Returns the current position, or throws [AppFailure] with a clear reason.
  Future<GeoPoint> getCurrentPosition({
    bool requestIfDenied = true,
  }) async {
    return (await getCurrentSample(requestIfDenied: requestIfDenied)).point;
  }

  /// Same permission checks as [getCurrentPosition], plus course over ground.
  Future<GpsSample> getCurrentSample({
    bool requestIfDenied = true,
  }) async {
    final enabled = await isServiceEnabled();
    if (!enabled) {
      throw const AppFailure(
        code: 'location_disabled',
        message:
            'Location services are turned off. Enable them to show your '
            'position on the map.',
      );
    }

    var permission = await checkPermission();
    if (permission == LocationPermission.denied && requestIfDenied) {
      permission = await requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const AppFailure(
        code: 'location_denied',
        message:
            'Location permission was denied. You can still browse the map '
            'and report hazards by adjusting the pin manually.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const AppFailure(
        code: 'location_denied_forever',
        message:
            'Location permission is permanently denied. Open system settings '
            'to allow PathAble to access your location.',
      );
    }

    final last = await Geolocator.getLastKnownPosition();
    if (last != null) return _sample(last);

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      ).timeout(const Duration(seconds: 8));
      return _sample(position);
    } on TimeoutException {
      throw const AppFailure(
        code: 'location_timeout',
        message:
            'GPS is taking too long. You can still search for a place and '
            'choose it as the start.',
      );
    }
  }

  Stream<GeoPoint> watchPosition({int distanceFilterMeters = 8}) {
    return watchSamples(distanceFilterMeters: distanceFilterMeters)
        .map((sample) => sample.point);
  }

  Stream<GpsSample> watchSamples({int distanceFilterMeters = 8}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
      ),
    ).map(_sample);
  }

  GpsSample _sample(Position position) {
    return GpsSample(
      point: GeoPoint(
        latitude: position.latitude,
        longitude: position.longitude,
      ),
      courseDegrees: position.hasHeading ? position.heading : null,
    );
  }
}
