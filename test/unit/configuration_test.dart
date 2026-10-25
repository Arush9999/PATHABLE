import 'package:flutter_test/flutter_test.dart';
import 'package:pathable/app/configuration.dart';

void main() {
  test('missing credentials force demonstration mode', () {
    const config = AppConfiguration(
      mode: 'production',
      supabaseUrl: '',
      supabaseAnonKey: '',
      mapStyleUrl: AppConfiguration.defaultMapStyleUrl,
      valhallaUrl: '',
      geocodingUrl: '',
    );

    expect(config.isDemoMode, isTrue);
    expect(config.hasSupabase, isFalse);
    expect(config.hasValhalla, isFalse);
    expect(config.requiresAccount, isFalse);
    expect(config.hasGoogleSignIn, isFalse);
  });

  test('demo defaults are labeled demo', () {
    final config = AppConfiguration.demoDefaults();
    expect(config.isDemoMode, isTrue);
    expect(config.mapStyleUrl, contains('demotiles.maplibre.org'));
  });

  test('supabase credentials require accounts and enable Google when set', () {
    const config = AppConfiguration(
      mode: 'production',
      supabaseUrl: 'https://example.supabase.co',
      supabaseAnonKey: 'anon',
      mapStyleUrl: AppConfiguration.defaultMapStyleUrl,
      valhallaUrl: 'http://127.0.0.1:8002',
      geocodingUrl: '',
      googleWebClientId: '123.apps.googleusercontent.com',
    );

    expect(config.isDemoMode, isFalse);
    expect(config.requiresAccount, isTrue);
    expect(config.hasGoogleSignIn, isTrue);
    expect(config.hasValhalla, isTrue);
  });
}
