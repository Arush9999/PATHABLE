import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend/supabase_client.dart';
import '../core/errors/app_failure.dart';
import '../core/location/location_service.dart';
import '../data/local/demo_data.dart';
import '../data/local/demo_hazard_repository.dart';
import '../data/local/local_hazard_store.dart';
import '../data/models/geo_point.dart';
import '../data/models/hazard.dart';
import '../data/repositories/hazard_repository.dart';
import '../data/repositories/supabase_hazard_repository.dart';
import '../data/services/auth_service.dart';
import '../data/services/passage_tracker.dart';
import '../data/services/geocoding_service.dart';
import '../data/services/maptiler_geocoding_service.dart';
import '../data/services/user_profile_service.dart';
import '../features/accessibility_profiles/accessibility_profile.dart';
import '../features/voice/voice_service.dart';
import '../routing/demo_routing_service.dart';
import '../routing/failover_routing_service.dart';
import '../routing/routing_models.dart';
import '../routing/routing_origin.dart';
import '../routing/routing_service.dart';
import '../routing/valhalla_routing_service.dart';
import 'configuration.dart';

export '../routing/routing_origin.dart';

final appConfigurationProvider = Provider<AppConfiguration>((ref) {
  throw UnimplementedError(
    'appConfigurationProvider must be overridden in ProviderScope',
  );
});

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in ProviderScope',
  );
});

/// User-chosen dark mode. Off (light green) until turned on in Settings.
final darkModeProvider = NotifierProvider<DarkModeNotifier, bool>(
  DarkModeNotifier.new,
);

class DarkModeNotifier extends Notifier<bool> {
  static const _key = 'dark_mode';

  @override
  bool build() {
    return ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await ref.read(sharedPreferencesProvider).setBool(_key, enabled);
  }
}

final locationServiceProvider = Provider<LocationService>((ref) {
  return const LocationService();
});

final userProfileServiceProvider = Provider<UserProfileService>((ref) {
  return const UserProfileService();
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(appConfigurationProvider));
});

/// Live Supabase auth session (null when signed out or Supabase unavailable).
final authSessionProvider = StreamProvider<Session?>((ref) async* {
  if (!PathAbleSupabase.isInitialized) {
    yield null;
    return;
  }
  final client = PathAbleSupabase.client;
  yield client.auth.currentSession;
  await for (final event in client.auth.onAuthStateChange) {
    yield event.session;
  }
});

final isSignedInProvider = Provider<bool>((ref) {
  return ref.watch(authSessionProvider).value != null;
});

final hazardRepositoryProvider = Provider<HazardRepository>((ref) {
  final config = ref.watch(appConfigurationProvider);
  if (!config.isDemoMode && PathAbleSupabase.isInitialized) {
    return SupabaseHazardRepository(PathAbleSupabase.client);
  }

  final prefs = ref.watch(sharedPreferencesProvider);
  final store = LocalHazardStore(prefs);
  final repo = DemoHazardRepository(store: store);
  ref.onDispose(repo.dispose);
  return repo;
});

final passageTrackerProvider = Provider<PassageTracker>((ref) {
  return PassageTracker(repository: ref.watch(hazardRepositoryProvider));
});

final geocodingServiceProvider = Provider<GeocodingService>((ref) {
  final config = ref.watch(appConfigurationProvider);
  if (config.hasGeocoding) {
    final origin = ref.watch(selectedOriginProvider);
    final gps = ref.watch(userLocationProvider).value;
    // Bias ambiguous names toward the traveler. A demo pin must not pin
    // worldwide search to Sugar Land. Specific place names still resolve globally.
    final GeoPoint? bias = (origin != null && !origin.isDemonstration)
        ? origin.location
        : gps;
    return HybridGeocodingService(
      primary: MapTilerGeocodingService(
        apiKey: config.mapTilerApiKey,
        baseUrl: config.geocodingUrl,
        proximity: bias,
      ),
    );
  }
  return DemoGeocodingService();
});

final routingServiceProvider = Provider<RoutingService>((ref) {
  final config = ref.watch(appConfigurationProvider);
  final hazards = ref.watch(hazardRepositoryProvider);
  // Paths and sidewalks via Valhalla. A path gap uses the sidewalk beside
  // the road, then rejoins a path. OSRM is not used because its public foot
  // profile follows vehicle travel lanes.
  final demo = DemoRoutingService(hazardRepository: hazards);
  final engines = <RoutingService>[
    if (config.hasValhalla)
      ValhallaRoutingService(
        endpoint: config.valhallaUrl,
        hazardRepository: hazards,
      ),
    if (config.isDemoMode || !config.hasValhalla) demo,
  ];
  if (engines.isEmpty) {
    return demo;
  }
  return FailoverRoutingService(engines: engines);
});

final voiceServiceProvider = Provider<VoiceService>((ref) {
  final service = DeviceVoiceService(
    audioEnabled: () => ref
        .read(accessibilityProfileProvider)
        .preferences
        .spokenInstructions,
  );
  ref.onDispose(service.stop);
  return service;
});

final accessibilityProfileProvider =
    NotifierProvider<AccessibilityProfileNotifier, AccessibilityProfile>(
  AccessibilityProfileNotifier.new,
);

class AccessibilityProfileNotifier extends Notifier<AccessibilityProfile> {
  static const _presetKey = 'accessibility_preset';
  static const _profileJsonKey = 'accessibility_profile_json';

  @override
  AccessibilityProfile build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final jsonRaw = prefs.getString(_profileJsonKey);
    if (jsonRaw != null && jsonRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(jsonRaw) as Map<String, dynamic>;
        return AccessibilityProfile.fromJson(decoded);
      } catch (_) {
        // Fall through to preset.
      }
    }
    final stored = prefs.getString(_presetKey);
    if (stored == null) {
      return AccessibilityProfile.fromPreset(ProfilePreset.generalPedestrian);
    }
    final preset = ProfilePreset.values.firstWhere(
      (value) => value.name == stored,
      orElse: () => stored == 'blindLowVision'
          ? ProfilePreset.blind
          : ProfilePreset.generalPedestrian,
    );
    return AccessibilityProfile.fromPreset(preset);
  }

  Future<void> _persist(AccessibilityProfile profile) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_presetKey, profile.preset.name);
    await prefs.setString(_profileJsonKey, jsonEncode(profile.toJson()));
  }

  Future<void> applyPreset(ProfilePreset preset) async {
    state = AccessibilityProfile.fromPreset(preset);
    await _persist(state);
    unawaited(pushRemote());
  }

  Future<void> updatePreferences(
    AccessibilityRoutingPreferences preferences,
  ) async {
    state = state.copyWith(
      preset: ProfilePreset.custom,
      preferences: preferences,
    );
    await _persist(state);
    unawaited(pushRemote());
  }

  Future<void> setHaptics(bool enabled) async {
    state = state.copyWith(hapticAlerts: enabled);
    await _persist(state);
    unawaited(pushRemote());
  }

  Future<void> pullRemote() async {
    final remote =
        await ref.read(userProfileServiceProvider).loadRemotePreferences();
    if (remote == null) return;
    state = remote;
    await _persist(state);
  }

  Future<void> pushRemote({bool syncEnabled = true}) async {
    await ref.read(userProfileServiceProvider).saveRemotePreferences(
          state,
          syncEnabled: syncEnabled,
        );
  }
}

final selectedDestinationProvider =
    NotifierProvider<SelectedDestinationNotifier, PlaceSuggestion?>(
  SelectedDestinationNotifier.new,
);

class SelectedDestinationNotifier extends Notifier<PlaceSuggestion?> {
  @override
  PlaceSuggestion? build() => null;

  void select(PlaceSuggestion? place) => state = place;
}

final selectedOriginProvider =
    NotifierProvider<SelectedOriginNotifier, PlaceSuggestion?>(
  SelectedOriginNotifier.new,
);

class SelectedOriginNotifier extends Notifier<PlaceSuggestion?> {
  @override
  PlaceSuggestion? build() => null;

  void select(PlaceSuggestion? place) => state = place;

  void useCurrentLocation(GeoPoint point) {
    state = PlaceSuggestion(
      id: gpsOriginId,
      name: 'My location',
      location: point,
    );
  }

  void useDemoStart() {
    state = PlaceSuggestion(
      id: demoOriginId,
      name: '${DemoData.environmentName} start',
      location: DemoData.startLocation,
      isDemonstration: true,
    );
  }
}

final activeRouteProvider =
    NotifierProvider<ActiveRouteNotifier, ScoredRoute?>(ActiveRouteNotifier.new);

class ActiveRouteNotifier extends Notifier<ScoredRoute?> {
  @override
  ScoredRoute? build() => null;

  void setRoute(ScoredRoute route) => state = route;

  void clear() => state = null;
}

final activeTravelModeProvider =
    NotifierProvider<ActiveTravelModeNotifier, TravelMode>(
  ActiveTravelModeNotifier.new,
);

class ActiveTravelModeNotifier extends Notifier<TravelMode> {
  @override
  TravelMode build() => TravelMode.pedestrian;

  void setMode(TravelMode mode) => state = mode;
}

final mapCenterProvider = NotifierProvider<MapCenterNotifier, GeoPoint>(
  MapCenterNotifier.new,
);

class MapCenterNotifier extends Notifier<GeoPoint> {
  @override
  GeoPoint build() {
    return DemoData.startLocation;
  }

  void setCenter(GeoPoint point) => state = point;
}

/// Latest GPS course over ground, or null when the fix has no bearing.
final gpsCourseProvider = NotifierProvider<GpsCourseNotifier, double?>(
  GpsCourseNotifier.new,
);

class GpsCourseNotifier extends Notifier<double?> {
  @override
  double? build() => null;

  void publish(double? courseDegrees) => state = courseDegrees;
}

final userLocationProvider =
    AsyncNotifierProvider<UserLocationNotifier, GeoPoint?>(
  UserLocationNotifier.new,
);

class UserLocationNotifier extends AsyncNotifier<GeoPoint?> {
  @override
  Future<GeoPoint?> build() async {
    return _acquire(moveMap: true);
  }

  /// Publishes a fix that already came from the device. Does not invent one.
  void publish(GeoPoint point) {
    ref.read(locationNoticeProvider.notifier).clear();
    state = AsyncData(point);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await _acquire(moveMap: true));
  }

  Future<GeoPoint?> _acquire({required bool moveMap}) async {
    final service = ref.read(locationServiceProvider);
    try {
      final sample = await service.getCurrentSample();
      ref.read(gpsCourseProvider.notifier).publish(sample.courseDegrees);
      if (moveMap) {
        ref.read(mapCenterProvider.notifier).setCenter(sample.point);
      }
      ref.read(locationNoticeProvider.notifier).clear();
      return sample.point;
    } on AppFailure catch (error) {
      ref.read(locationNoticeProvider.notifier).set(error.message);
      return null;
    } catch (error) {
      ref.read(locationNoticeProvider.notifier).set(
            'Location could not be read. $error',
          );
      return null;
    }
  }
}

/// Plain-language location status. Null means the last GPS read succeeded.
final locationNoticeProvider =
    NotifierProvider<LocationNoticeNotifier, String?>(
  LocationNoticeNotifier.new,
);

class LocationNoticeNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? message) => state = message;

  void clear() => state = null;
}

final nearbyHazardsProvider =
    FutureProvider.autoDispose<List<Hazard>>((ref) async {
  final center = ref.watch(mapCenterProvider);
  final repo = ref.watch(hazardRepositoryProvider);
  return repo.getNearbyHazards(center: center, radiusMeters: 12000);
});

final selectedHazardIdProvider =
    NotifierProvider<SelectedHazardNotifier, String?>(
  SelectedHazardNotifier.new,
);

class SelectedHazardNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}
