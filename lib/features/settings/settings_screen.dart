import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/widgets/demo_banner.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigurationProvider);
    final darkMode = ref.watch(darkModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          tooltip: 'Back to map',
          onPressed: () => context.go(AppRoutes.map),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ListView(
        children: [
          if (config.isDemoMode) const DemoBanner(),
          SwitchListTile(
            secondary: Icon(darkMode ? Icons.dark_mode : Icons.light_mode),
            title: const Text('Dark mode'),
            subtitle: const Text('Green theme with darker surfaces'),
            value: darkMode,
            onChanged: (value) {
              ref.read(darkModeProvider.notifier).setEnabled(value);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Account'),
            subtitle: Text(
              config.requiresAccount
                  ? 'Email or Google sign-in'
                  : 'Sign in when Supabase is connected',
            ),
            onTap: () => context.push(AppRoutes.account),
          ),
          ListTile(
            leading: const Icon(Icons.accessibility_new),
            title: const Text('Accessibility profiles'),
            subtitle: const Text(
              'Blind, low vision, wheelchair, cycling, and audio',
            ),
            onTap: () => context.push(AppRoutes.accessibility),
          ),
        ],
      ),
    );
  }
}
