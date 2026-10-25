import 'package:supabase_flutter/supabase_flutter.dart';

import '../../backend/supabase_client.dart';
import '../../features/accessibility_profiles/accessibility_profile.dart';

/// Loads and saves signed-in user profile metadata + accessibility preferences.
class UserProfileService {
  const UserProfileService();

  User? get currentUser =>
      PathAbleSupabase.isInitialized
          ? PathAbleSupabase.client.auth.currentUser
          : null;

  String? get displayName {
    final user = currentUser;
    if (user == null) return null;
    final meta = user.userMetadata ?? const <String, dynamic>{};
    final name = meta['display_name'] as String?;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    return user.email?.split('@').first;
  }

  Future<void> updateDisplayName(String name) async {
    if (!PathAbleSupabase.isInitialized) {
      throw StateError('Supabase is not connected.');
    }
    final trimmed = name.trim();
    await PathAbleSupabase.client.auth.updateUser(
      UserAttributes(data: {'display_name': trimmed}),
    );
  }

  Future<AccessibilityProfile?> loadRemotePreferences() async {
    final user = currentUser;
    if (user == null || !PathAbleSupabase.isInitialized) return null;

    final row = await PathAbleSupabase.client
        .from('user_preferences')
        .select('profile_json, sync_enabled')
        .eq('user_id', user.id)
        .maybeSingle();

    if (row == null) return null;
    final syncEnabled = row['sync_enabled'] as bool? ?? false;
    if (!syncEnabled) return null;

    final json = row['profile_json'];
    if (json is Map<String, dynamic>) {
      return AccessibilityProfile.fromJson(json);
    }
    if (json is Map) {
      return AccessibilityProfile.fromJson(Map<String, dynamic>.from(json));
    }
    return null;
  }

  Future<void> saveRemotePreferences(
    AccessibilityProfile profile, {
    bool syncEnabled = true,
  }) async {
    final user = currentUser;
    if (user == null || !PathAbleSupabase.isInitialized) return;

    await PathAbleSupabase.client.from('user_preferences').upsert({
      'user_id': user.id,
      'profile_json': profile.toJson(),
      'sync_enabled': syncEnabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
