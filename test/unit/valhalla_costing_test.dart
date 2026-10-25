import 'package:flutter_test/flutter_test.dart';
import 'package:pathable/data/models/geo_point.dart';
import 'package:pathable/routing/routing_models.dart';
import 'package:pathable/routing/valhalla_routing_service.dart';

void main() {
  const origin = GeoPoint(latitude: 29.55, longitude: -95.58);
  const destination = GeoPoint(latitude: 29.56, longitude: -95.57);

  RoutingRequest request(
    TravelMode mode, {
    AccessibilityRoutingPreferences preferences =
        const AccessibilityRoutingPreferences(),
  }) {
    return RoutingRequest(
      origin: origin,
      destination: destination,
      mode: mode,
      preferences: preferences,
    );
  }

  Map<String, dynamic> pedestrianOf(RoutingRequest request) {
    final options = valhallaCostingOptions(request);
    return options['pedestrian']! as Map<String, dynamic>;
  }

  test('pedestrian costing prefers footways, then sidewalks beside the road', () {
    final pedestrian = pedestrianOf(request(TravelMode.pedestrian));

    expect(pedestrian.containsKey('use_roads'), isFalse);
    expect(pedestrian['walkway_factor'], kValhallaWalkwayFactor);
    expect(pedestrian['sidewalk_factor'], kValhallaSidewalkFactor);
    expect(pedestrian['alley_factor'], kValhallaAlleyFactor);
    expect(pedestrian['driveway_factor'], kValhallaDrivewayFactor);

    expect(pedestrian['walkway_factor'], lessThan(pedestrian['sidewalk_factor']));
    expect(pedestrian['sidewalk_factor'], lessThan(1));
    expect(pedestrian['alley_factor'], greaterThan(1));
    expect(pedestrian['driveway_factor'], greaterThan(1));
    expect(pedestrian['service_factor'], greaterThan(1));
  });

  test('wheelchair mode keeps the path and sidewalk factors', () {
    final pedestrian = pedestrianOf(
      request(
        TravelMode.pedestrian,
        preferences: const AccessibilityRoutingPreferences(wheelchairMode: true),
      ),
    );

    expect(pedestrian['walkway_factor'], kValhallaWalkwayFactor);
    expect(pedestrian['sidewalk_factor'], kValhallaSidewalkFactor);
    expect(pedestrian['alley_factor'], greaterThan(1));
    expect(pedestrian.containsKey('use_roads'), isFalse);
    expect(pedestrian['walking_speed'], 3.5);
  });

  test('bicycle costing uses roads only as a path gap', () {
    final options = valhallaCostingOptions(request(TravelMode.cycling));
    final bicycle = options['bicycle']! as Map<String, dynamic>;

    expect(bicycle['use_roads'], kValhallaBicycleUseRoads);
    expect(bicycle['use_roads'], 0.0);
    expect(bicycle.containsKey('sidewalk_factor'), isFalse);
    expect(bicycle.containsKey('bikeshare_factor'), isFalse);
    expect(options.containsKey('pedestrian'), isFalse);
  });
}
