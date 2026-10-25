import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/configuration.dart';

/// Initializes the public Supabase client. Never accepts a service-role key.
class PathAbleSupabase {
  PathAbleSupabase._();

  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  static SupabaseClient get client {
    if (!_initialized) {
      throw StateError('Supabase has not been initialized.');
    }
    return Supabase.instance.client;
  }

  static Future<bool> initialize(AppConfiguration config) async {
    if (!config.hasSupabase) {
      _initialized = false;
      return false;
    }

    // PKCE on every platform. Web sign-up sends the browser origin
    // (http://127.0.0.1:8081 or http://localhost:8081) as redirectTo so
    // confirmation mail does not use a mobile deep link. Password sign-in
    // does not redirect.
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    _initialized = true;
    return true;
  }
}
