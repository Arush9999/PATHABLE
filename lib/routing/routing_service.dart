import 'routing_models.dart';

/// Replaceable routing engine contract.
///
/// Valhalla (or another engine) returns candidate geometries; PathAble then
/// applies hazard-aware scoring. Engines must not claim hazard awareness alone.
abstract class RoutingService {
  Future<RoutingResult> planRoute(RoutingRequest request);

  String get engineName;

  bool get isDemonstration;
}
