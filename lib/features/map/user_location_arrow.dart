import 'dart:io' show zlib;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/location/device_heading.dart';
import '../../data/models/geo_point.dart';

/// Chevron puck for the signed-in or anonymous GPS fix.
///
/// MapLibre symbols rotate with [iconRotate] once an image is registered.
/// The chevron is drawn in memory (no asset file) and aligned to the map,
/// so heading 0 points north and 90 points east.
class UserLocationArrow {
  static const imageId = 'pathable-gps-arrow';
  static const sourceId = 'pathable-gps-arrow-source';
  static const layerId = 'pathable-gps-arrow-layer';

  int _generation = 0;
  bool _ready = false;
  Future<void> _tail = Future<void>.value();

  /// Style reloads drop images and sources. The next [sync] rebuilds them.
  void reset() {
    _generation++;
    _ready = false;
  }

  Future<void> sync(
    MapLibreMapController controller, {
    required GeoPoint? point,
    required double headingDegrees,
  }) {
    final generation = _generation;
    final heading = headingDegrees.isFinite
        ? normalizeHeading(headingDegrees)
        : 0.0;
    final next = _tail.then((_) async {
      try {
        await _syncBody(controller, point, heading, generation);
      } catch (error) {
        debugPrint('Location arrow sync deferred: $error');
        _ready = false;
      }
    });
    _tail = next;
    return next;
  }

  Future<void> _syncBody(
    MapLibreMapController controller,
    GeoPoint? point,
    double heading,
    int generation,
  ) async {
    if (generation != _generation) return;
    if (!_ready) {
      try {
        await controller.addImage(imageId, locationArrowPng());
      } catch (error) {
        debugPrint('Location arrow image: $error');
      }
      if (generation != _generation) return;
      try {
        await controller.addGeoJsonSource(sourceId, _features(null, 0));
        await controller.addSymbolLayer(
          sourceId,
          layerId,
          const SymbolLayerProperties(
            iconImage: imageId,
            iconSize: 1.15,
            iconRotate: [Expressions.get, 'heading'],
            iconRotationAlignment: 'map',
            iconPitchAlignment: 'viewport',
            iconAllowOverlap: true,
            iconIgnorePlacement: true,
            iconAnchor: 'center',
          ),
          enableInteraction: false,
        );
        _ready = true;
      } catch (error) {
        debugPrint('Location arrow layer: $error');
        try {
          await controller.setGeoJsonSource(sourceId, _features(null, 0));
          _ready = true;
        } catch (updateError) {
          debugPrint('Location arrow source: $updateError');
          _ready = false;
          return;
        }
      }
    }
    if (generation != _generation || !_ready) return;
    await controller.setGeoJsonSource(sourceId, _features(point, heading));
  }
}

Map<String, dynamic> _features(GeoPoint? point, double heading) {
  if (point == null) {
    return {
      'type': 'FeatureCollection',
      'features': <Map<String, dynamic>>[],
    };
  }
  return {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': {'heading': heading},
        'geometry': {
          'type': 'Point',
          'coordinates': [point.longitude, point.latitude],
        },
      },
    ],
  };
}

Uint8List? _arrowPng;

/// Upward chevron, blue with a white halo. Heading rotation is done by the map.
Uint8List locationArrowPng() => _arrowPng ??= _encodeArrowPng();

Uint8List _encodeArrowPng() {
  const size = 64;
  const blue = [11, 110, 153, 255];
  const white = [255, 255, 255, 255];
  const chevron = <List<double>>[
    [32, 5],
    [54, 46],
    [32, 34],
    [10, 46],
  ];

  final rgba = Uint8List(size * size * 4);
  final inside = List<bool>.filled(size * size, false);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      inside[y * size + x] = _contains(chevron, x + 0.5, y + 0.5);
    }
  }

  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final filled = inside[y * size + x];
      var halo = false;
      if (!filled) {
        for (var dy = -3; dy <= 3 && !halo; dy++) {
          for (var dx = -3; dx <= 3; dx++) {
            final nx = x + dx;
            final ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= size || ny >= size) continue;
            if (inside[ny * size + nx]) {
              halo = true;
              break;
            }
          }
        }
      }
      if (!filled && !halo) continue;
      final color = filled ? blue : white;
      final offset = (y * size + x) * 4;
      rgba[offset] = color[0];
      rgba[offset + 1] = color[1];
      rgba[offset + 2] = color[2];
      rgba[offset + 3] = color[3];
    }
  }
  return _encodeRgbaPng(size, size, rgba);
}

bool _contains(List<List<double>> polygon, double x, double y) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final xi = polygon[i][0];
    final yi = polygon[i][1];
    final xj = polygon[j][0];
    final yj = polygon[j][1];
    final crosses = (yi > y) != (yj > y);
    if (!crosses) continue;
    final xAtY = (xj - xi) * (y - yi) / (yj - yi) + xi;
    if (x < xAtY) inside = !inside;
  }
  return inside;
}

Uint8List _encodeRgbaPng(int width, int height, Uint8List rgba) {
  final raw = BytesBuilder(copy: false);
  final stride = width * 4;
  for (var y = 0; y < height; y++) {
    raw.addByte(0);
    raw.add(rgba.sublist(y * stride, y * stride + stride));
  }

  final ihdr = BytesBuilder(copy: false)
    ..add(_u32(width))
    ..add(_u32(height))
    ..addByte(8)
    ..addByte(6)
    ..addByte(0)
    ..addByte(0)
    ..addByte(0);

  final png = BytesBuilder(copy: false)
    ..add(const [137, 80, 78, 71, 13, 10, 26, 10])
    ..add(_chunk('IHDR', ihdr.toBytes()))
    ..add(_chunk('IDAT', Uint8List.fromList(zlib.encode(raw.toBytes()))))
    ..add(_chunk('IEND', Uint8List(0)));
  return png.toBytes();
}

Uint8List _chunk(String type, Uint8List data) {
  final typeBytes = Uint8List.fromList(type.codeUnits);
  final crcInput = Uint8List(typeBytes.length + data.length)
    ..setRange(0, typeBytes.length, typeBytes)
    ..setRange(typeBytes.length, typeBytes.length + data.length, data);
  return (BytesBuilder(copy: false)
        ..add(_u32(data.length))
        ..add(crcInput)
        ..add(_u32(_crc32(crcInput))))
      .toBytes();
}

int _crc32(Uint8List data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      if ((crc & 1) != 0) {
        crc = (crc >> 1) ^ 0xEDB88320;
      } else {
        crc = crc >> 1;
      }
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

Uint8List _u32(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.big);
  return data.buffer.asUint8List();
}
