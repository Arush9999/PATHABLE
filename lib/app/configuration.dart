import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Runtime application configuration loaded from environment variables.
///
/// Privileged service-role keys must never be placed here or in the mobile app.
class AppConfiguration {
  const AppConfiguration({
    required this.mode,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.mapStyleUrl,
    required this.valhallaUrl,
    required this.geocodingUrl,
    this.mapTilerApiKey = '',
    this.googleWebClientId = '',
    this.googleIosClientId = '',
  });

  /// `demo` or `production`.
  final String mode;
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String mapStyleUrl;
  final String valhallaUrl;
  final String geocodingUrl;
  final String mapTilerApiKey;

  /// OAuth 2.0 Web client ID from Google Cloud (required for Google Sign-In
  /// ID tokens accepted by Supabase).
  final String googleWebClientId;

  /// iOS OAuth client ID from Google Cloud (iOS / macOS only).
  final String googleIosClientId;

  static const String defaultMapStyleUrl =
      'https://demotiles.maplibre.org/style.json';

  /// True when the app should use local demonstration services.
  bool get isDemoMode {
    if (mode.toLowerCase() == 'demo') {
      return true;
    }
    // Without backend credentials, fall back to demonstration mode.
    return supabaseUrl.isEmpty || supabaseAnonKey.isEmpty;
  }

  bool get hasValhalla => valhallaUrl.isNotEmpty;

  bool get hasGeocoding => geocodingUrl.isNotEmpty && mapTilerApiKey.isNotEmpty;

  bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Accounts are required whenever Supabase is configured.
  bool get requiresAccount => hasSupabase;

  bool get hasGoogleSignIn => googleWebClientId.isNotEmpty;

  factory AppConfiguration.fromEnvironment() {
    String read(String key, [String fallback = '']) {
      final value = dotenv.maybeGet(key);
      if (value == null || value.trim().isEmpty) {
        return fallback;
      }
      return value.trim();
    }

    final mapStyle = read('MAP_STYLE_URL', defaultMapStyleUrl);
    var mapTilerKey = read('MAPTILER_API_KEY');
    if (mapTilerKey.isEmpty) {
      final match = RegExp(r'[?&]key=([^&]+)').firstMatch(mapStyle);
      mapTilerKey = match?.group(1) ?? '';
    }

    return AppConfiguration(
      mode: read('PATHABLE_MODE', 'demo'),
      supabaseUrl: read('SUPABASE_URL'),
      supabaseAnonKey: read('SUPABASE_ANON_KEY'),
      mapStyleUrl: mapStyle,
      valhallaUrl: read('VALHALLA_URL'),
      geocodingUrl: read('GEOCODING_URL'),
      mapTilerApiKey: mapTilerKey,
      googleWebClientId: read('GOOGLE_WEB_CLIENT_ID'),
      googleIosClientId: read('GOOGLE_IOS_CLIENT_ID'),
    );
  }

  /// Safe configuration used when dotenv assets are unavailable (e.g. tests).
  factory AppConfiguration.demoDefaults() {
    return const AppConfiguration(
      mode: 'demo',
      supabaseUrl: '',
      supabaseAnonKey: '',
      mapStyleUrl: defaultMapStyleUrl,
      valhallaUrl: '',
      geocodingUrl: '',
      mapTilerApiKey: '',
      googleWebClientId: '',
      googleIosClientId: '',
    );
  }
}
