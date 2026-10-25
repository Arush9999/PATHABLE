import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/configuration.dart';
import 'app/providers.dart';
import 'backend/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = await _loadConfiguration();
  if (config.hasSupabase) {
    try {
      await PathAbleSupabase.initialize(config).timeout(
        const Duration(seconds: 8),
      );
    } catch (_) {
      // A hung token refresh must not leave the phone on a blank launch screen.
    }
  }

  final prefs = await SharedPreferences.getInstance();
  final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;

  runApp(
    ProviderScope(
      overrides: [
        appConfigurationProvider.overrideWithValue(config),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: PathAbleApp(showOnboarding: !onboardingComplete),
    ),
  );
}

Future<AppConfiguration> _loadConfiguration() async {
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    try {
      await dotenv.load(fileName: 'assets/config/.env');
    } catch (_) {
      return AppConfiguration.demoDefaults();
    }
  }
  return AppConfiguration.fromEnvironment();
}
