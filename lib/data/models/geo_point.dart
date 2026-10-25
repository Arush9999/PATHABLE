import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// Geographic point using WGS84 latitude/longitude.
class GeoPoint extends Equatable {
  const GeoPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  bool get isValid =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  /// Parses GeoJSON maps, WKT/EWKT strings, or PostGIS EWKB hex payloads.
  factory GeoPoint.parseLocation(Object? raw) {
    if (raw == null) {
      throw const FormatException('Location payload is null');
    }

    if (raw is GeoPoint) {
      return raw;
    }

    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final coordinates = map['coordinates'];
      if (coordinates is List && coordinates.length >= 2) {
        return GeoPoint(
          latitude: (coordinates[1] as num).toDouble(),
          longitude: (coordinates[0] as num).toDouble(),
        );
      }
      final lat = map['latitude'] ?? map['lat'];
      final lng = map['longitude'] ?? map['lng'] ?? map['lon'];
      if (lat is num && lng is num) {
        return GeoPoint(latitude: lat.toDouble(), longitude: lng.toDouble());
      }
    }

    if (raw is String) {
      final text = raw.trim();
      final wkt = RegExp(
        r'POINT\s*\(\s*([-\d.]+)\s+([-\d.]+)\s*\)',
        caseSensitive: false,
      ).firstMatch(text);
      if (wkt != null) {
        return GeoPoint(
          latitude: double.parse(wkt.group(2)!),
          longitude: double.parse(wkt.group(1)!),
        );
      }

      // PostGIS often returns geography/geometry as EWKB hex via PostgREST.
      if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(text) && text.length >= 42) {
        final fromWkb = _tryParseEwkbPoint(text);
        if (fromWkb != null) return fromWkb;
      }
    }

    throw FormatException('Unsupported location payload: $raw');
  }

  /// Little-endian WKB/EWKB Point → (lon, lat).
  static GeoPoint? _tryParseEwkbPoint(String hex) {
    try {
      final bytes = _hexToBytes(hex);
      if (bytes.length < 21) return null;

      final data = ByteData.sublistView(bytes);
      final littleEndian = data.getUint8(0) == 1;
      final endian = littleEndian ? Endian.little : Endian.big;
      var offset = 1;

      final typeWord = data.getUint32(offset, endian);
      offset += 4;

      // EWKB SRID flag: 0x20000000
      final hasSrid = (typeWord & 0x20000000) != 0;
      final type = typeWord & 0xFF;
      if (type != 1) {
        // Only Point is supported for hazard locations.
        return null;
      }
      if (hasSrid) {
        offset += 4; // skip SRID
      }
      if (offset + 16 > bytes.length) return null;

      final longitude = data.getFloat64(offset, endian);
      final latitude = data.getFloat64(offset + 8, endian);
      return GeoPoint(latitude: latitude, longitude: longitude);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _hexToBytes(String hex) {
    final length = hex.length ~/ 2;
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  @override
  List<Object?> get props => [latitude, longitude];

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}
