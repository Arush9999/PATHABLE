import '../data/local/demo_data.dart';
import '../data/models/geo_point.dart';
import '../data/services/geocoding_service.dart';

/// Ids that are not a user-typed start address.
const gpsOriginId = 'gps-origin';
const demoOriginId = 'demo-origin';

/// True when the user picked a place or the demonstration pin.
///
/// A GPS snapshot is not sticky: a newer fix replaces it.
bool originIsChosenAddress(PlaceSuggestion? place) {
  if (place == null) return false;
  return place.id != gpsOriginId;
}

/// Explicit start address, otherwise a real GPS fix, otherwise the demo pin.
///
/// A missing GPS fix is never reported as a successful location.
GeoPoint routingOriginFor({
  PlaceSuggestion? selectedOrigin,
  GeoPoint? gps,
}) {
  if (originIsChosenAddress(selectedOrigin)) {
    return selectedOrigin!.location;
  }
  if (gps != null) return gps;
  if (selectedOrigin != null) return selectedOrigin.location;
  return DemoData.startLocation;
}

String routingOriginLabel({
  PlaceSuggestion? selectedOrigin,
  GeoPoint? gps,
}) {
  if (originIsChosenAddress(selectedOrigin)) return selectedOrigin!.name;
  if (gps != null) return 'My location';
  return 'Start not set';
}

String routingOriginSubtitle({
  PlaceSuggestion? selectedOrigin,
  GeoPoint? gps,
}) {
  if (selectedOrigin?.id == demoOriginId) {
    return 'Demonstration start pin, not a GPS fix.';
  }
  if (originIsChosenAddress(selectedOrigin)) {
    return 'Chosen start address';
  }
  if (gps != null) {
    return 'GPS position. Tap to set a different start.';
  }
  return 'GPS unavailable. This is the demonstration pin, not a live fix.';
}
