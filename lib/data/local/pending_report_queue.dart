import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/geo_point.dart';
import '../models/hazard.dart';

/// Local drafts that are NOT treated as submitted until the server accepts them.
class PendingReportQueue {
  PendingReportQueue(this._prefs);

  static const storageKey = 'pathable_pending_reports_v1';
  final SharedPreferences _prefs;
  final _uuid = const Uuid();

  List<Hazard> load() {
    final raw = _prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => _fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Hazard> enqueue(Hazard draft) async {
    final items = [...load()];
    final pending = Hazard(
      id: draft.id.isEmpty ? 'pending-${_uuid.v4()}' : draft.id,
      category: draft.category,
      severity: draft.severity,
      status: HazardStatus.provisional,
      location: draft.location,
      confidenceScore: draft.confidenceScore,
      createdAt: draft.createdAt,
      updatedAt: DateTime.now().toUtc(),
      description: draft.description,
      photoPath: draft.photoPath,
      isDemonstration: draft.isDemonstration,
    );
    items.add(pending);
    await _save(items);
    return pending;
  }

  Future<void> remove(String id) async {
    final items = load().where((h) => h.id != id).toList(growable: false);
    await _save(items);
  }

  Future<void> _save(List<Hazard> items) async {
    final payload = jsonEncode(items.map(_toJson).toList(growable: false));
    await _prefs.setString(storageKey, payload);
  }

  Map<String, dynamic> _toJson(Hazard hazard) => {
        'id': hazard.id,
        'category': hazard.category.name,
        'severity': hazard.severity.name,
        'status': hazard.status.name,
        'latitude': hazard.location.latitude,
        'longitude': hazard.location.longitude,
        'confidenceScore': hazard.confidenceScore,
        'createdAt': hazard.createdAt.toIso8601String(),
        'updatedAt': hazard.updatedAt.toIso8601String(),
        'description': hazard.description,
        'photoPath': hazard.photoPath,
        'isDemonstration': hazard.isDemonstration,
      };

  Hazard _fromJson(Map<String, dynamic> json) {
    return Hazard(
      id: json['id'] as String,
      category: HazardCategory.values.byName(json['category'] as String),
      severity: HazardSeverity.values.byName(json['severity'] as String),
      status: HazardStatus.values.byName(json['status'] as String),
      location: GeoPoint(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      ),
      confidenceScore: (json['confidenceScore'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      description: json['description'] as String?,
      photoPath: json['photoPath'] as String?,
      isDemonstration: json['isDemonstration'] as bool? ?? false,
    );
  }
}
