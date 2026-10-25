import 'routing_models.dart';
import 'routing_service.dart';

/// Tries engines in order until one returns usable road-following routes.
class FailoverRoutingService implements RoutingService {
  FailoverRoutingService({
    required this.engines,
  }) : assert(engines.isNotEmpty);

  /// Convenience for the common primary → fallback pair.
  factory FailoverRoutingService.pair({
    required RoutingService primary,
    required RoutingService fallback,
  }) {
    return FailoverRoutingService(engines: [primary, fallback]);
  }

  final List<RoutingService> engines;

  @override
  String get engineName => engines.first.engineName;

  @override
  bool get isDemonstration => false;

  @override
  Future<RoutingResult> planRoute(RoutingRequest request) async {
    Object? lastError;
    for (var i = 0; i < engines.length; i++) {
      final engine = engines[i];
      try {
        final result = await engine.planRoute(request);
        if (result.routes.isEmpty) continue;

        // Prefer non-demo engines; only accept demo if nothing else worked.
        if (result.isDemonstration && i < engines.length - 1) {
          continue;
        }

        if (i == 0) return result;

        return RoutingResult(
          routes: result.routes,
          isDemonstration: result.isDemonstration,
          limitations: [
            ...result.limitations,
            'Primary router unavailable — using ${engine.engineName}.',
          ],
        );
      } catch (error) {
        lastError = error;
      }
    }

    throw lastError ??
        StateError('No routing engines produced a route.');
  }
}
