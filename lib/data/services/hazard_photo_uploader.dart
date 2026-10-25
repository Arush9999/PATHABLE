import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Uploads optional report photos to the `hazard-photos` Storage bucket.
class HazardPhotoUploader {
  HazardPhotoUploader(this._client);

  final SupabaseClient _client;
  final _uuid = const Uuid();

  static const bucket = 'hazard-photos';

  /// Returns a storage object key, or null when [localPath] is empty/remote.
  Future<String?> uploadIfLocal(String? localPath) async {
    if (localPath == null || localPath.trim().isEmpty) {
      return null;
    }
    if (!_looksLocal(localPath)) {
      return localPath;
    }

    final file = File(localPath);
    if (!await file.exists()) {
      return null;
    }

    final bytes = await file.readAsBytes();
    final ext = _extension(localPath);
    final userSegment = _client.auth.currentUser?.id ?? 'anon';
    final objectPath = '$userSegment/${_uuid.v4()}.$ext';

    await _client.storage.from(bucket).uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(
            contentType: _contentType(ext),
            upsert: false,
          ),
        );

    return objectPath;
  }

  bool _looksLocal(String path) {
    return path.startsWith('/') ||
        path.contains(r'\') ||
        path.startsWith('file:') ||
        RegExp(r'^[A-Za-z]:\\').hasMatch(path);
  }

  String _extension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    return 'jpg';
  }

  String _contentType(String ext) => switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
}
