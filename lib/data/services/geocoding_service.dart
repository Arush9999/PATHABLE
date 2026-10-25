import '../local/demo_data.dart';
import '../models/geo_point.dart';

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.id,
    required this.name,
    required this.location,
    this.isDemonstration = false,
  });

  final String id;
  final String name;
  final GeoPoint location;
  final bool isDemonstration;
}

abstract class GeocodingService {
  Future<List<PlaceSuggestion>> search(String query);
  bool get isDemonstration;
}

class DemoGeocodingService implements GeocodingService {
  @override
  bool get isDemonstration => true;

  @override
  Future<List<PlaceSuggestion>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return DemoData.destinations
          .map(
            (d) => PlaceSuggestion(
              id: d.id,
              name: d.name,
              location: d.location,
              isDemonstration: true,
            ),
          )
          .toList(growable: false);
    }

    return DemoData.destinations
        .where((d) => d.name.toLowerCase().contains(q))
        .map(
          (d) => PlaceSuggestion(
            id: d.id,
            name: d.name,
            location: d.location,
            isDemonstration: true,
          ),
        )
        .toList(growable: false);
  }
}
