import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/errors/app_failure.dart';
import '../models/geo_point.dart';
import 'geocoding_service.dart';

/// Worldwide MapTiler forward geocoding.
///
/// There is no country filter. [proximity] only reorders ambiguous matches
/// toward the traveler (GPS or a chosen start), the same way a maps app does.
/// A specific place name still resolves anywhere in the world.
///
/// Docs: https://docs.maptiler.com/cloud/api/geocoding/
class MapTilerGeocodingService implements GeocodingService {
  MapTilerGeocodingService({
    required this.apiKey,
    this.baseUrl = 'https://api.maptiler.com/geocoding',
    this.proximity,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String apiKey;
  final String baseUrl;

  /// Optional lon/lat bias. Null keeps pure worldwide text ranking.
  final GeoPoint? proximity;
  final http.Client _http;

  @override
  bool get isDemonstration => false;

  @override
  Future<List<PlaceSuggestion>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      return const [];
    }

    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    // Build with Uri.parse + pathSegments so spaces are encoded once.
    final parsed = Uri.parse(root);
    final uri = Uri(
      scheme: parsed.scheme.isEmpty ? 'https' : parsed.scheme,
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
      pathSegments: [
        ...parsed.pathSegments.where((s) => s.isNotEmpty),
        '$q.json',
      ],
      queryParameters: {
        'key': apiKey,
        'limit': '10',
        'language': 'en',
        'autocomplete': 'true',
        'fuzzyMatch': 'true',
        if (proximity != null)
          'proximity': '${proximity!.longitude},${proximity!.latitude}',
      },
    );

    final http.Response response;
    try {
      response = await _http.get(uri).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const AppFailure(
        code: 'geocoding_timeout',
        message: 'Search is taking too long. Check the phone’s internet and try again.',
      );
    }
    if (response.statusCode == 429) {
      throw const AppFailure(
        code: 'geocoding_rate_limit',
        message: 'Geocoding rate limit reached. Try again shortly.',
      );
    }
    if (response.statusCode >= 400) {
      debugPrint(
        'MapTiler geocode HTTP ${response.statusCode}: ${response.body}',
      );
      throw AppFailure(
        code: 'geocoding_error',
        message: 'Geocoding failed (HTTP ${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final features = (decoded['features'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();

    final suggestions = <PlaceSuggestion>[];
    for (final feature in features) {
      final coordinates = _coordinatesOf(feature);
      if (coordinates == null) continue;

      final props = feature['properties'] as Map<String, dynamic>? ?? {};
      final name = (feature['place_name'] as String?) ??
          (feature['matching_place_name'] as String?) ??
          (props['place_name'] as String?) ??
          (feature['text'] as String?) ??
          (props['label'] as String?) ??
          (props['name'] as String?) ??
          'Place';

      suggestions.add(
        PlaceSuggestion(
          id: (feature['id'] ?? props['id'] ?? name).toString(),
          name: name,
          location: GeoPoint(
            latitude: coordinates.$2,
            longitude: coordinates.$1,
          ),
        ),
      );
    }
    return suggestions;
  }

  /// Returns (longitude, latitude) or null.
  static (double, double)? _coordinatesOf(Map<String, dynamic> feature) {
    final geometry = feature['geometry'] as Map<String, dynamic>?;
    final fromGeometry = _pairFromList(geometry?['coordinates']);
    if (fromGeometry != null) return fromGeometry;

    final fromCenter = _pairFromList(feature['center']);
    if (fromCenter != null) return fromCenter;

    final props = feature['properties'] as Map<String, dynamic>? ?? {};
    final fromProps = _pairFromList(props['coordinates']);
    if (fromProps != null) return fromProps;

    final lon = props['lon'] ?? props['lng'] ?? props['longitude'];
    final lat = props['lat'] ?? props['latitude'];
    if (lon is num && lat is num) {
      return (lon.toDouble(), lat.toDouble());
    }
    return null;
  }

  static (double, double)? _pairFromList(dynamic raw) {
    if (raw is! List || raw.length < 2) return null;
    final a = raw[0];
    final b = raw[1];
    if (a is num && b is num) {
      return (a.toDouble(), b.toDouble());
    }
    return null;
  }
}

/// Live worldwide geocoding. Local demo places are not mixed into results,
/// so a search cannot be replaced by a Riverstone favorite.
class HybridGeocodingService implements GeocodingService {
  HybridGeocodingService({
    required this.primary,
  });

  final GeocodingService primary;

  @override
  bool get isDemonstration => primary.isDemonstration;

  @override
  Future<List<PlaceSuggestion>> search(String query) {
    return primary.search(query);
  }
}
