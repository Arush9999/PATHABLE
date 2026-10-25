import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/widgets/demo_banner.dart';
import 'accessibility_profile.dart';

class AccessibilityProfileScreen extends ConsumerWidget {
  const AccessibilityProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(accessibilityProfileProvider);
    final config = ref.watch(appConfigurationProvider);
    final notifier = ref.read(accessibilityProfileProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Accessibility preferences')),
      body: ListView(
        children: [
          if (config.isDemoMode) const DemoBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Choose how PathAble routes and warns. '
              'You do not need to disclose a disability or diagnosis.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          ...ProfilePreset.values.where((preset) => preset != ProfilePreset.custom).map(
            (preset) {
              final option = AccessibilityProfile.fromPreset(preset);
              final selected = profile.preset == preset;
              return ListTile(
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(option.label),
                selected: selected,
                onTap: () => notifier.applyPreset(preset),
              );
            },
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Avoid stairs / inaccessible paths'),
            value: profile.preferences.avoidStairs,
            onChanged: (value) => notifier.updatePreferences(
              profile.preferences.copyWith(avoidStairs: value),
            ),
          ),
          SwitchListTile(
            title: const Text('Avoid missing curb ramps'),
            value: profile.preferences.avoidMissingCurbRamps,
            onChanged: (value) => notifier.updatePreferences(
              profile.preferences.copyWith(avoidMissingCurbRamps: value),
            ),
          ),
          SwitchListTile(
            title: const Text('Avoid confirmed closures'),
            value: profile.preferences.avoidImpassableClosures,
            onChanged: (value) => notifier.updatePreferences(
              profile.preferences.copyWith(avoidImpassableClosures: value),
            ),
          ),
          SwitchListTile(
            title: const Text('Prefer well-lit routes'),
            value: profile.preferences.preferWellLit,
            onChanged: (value) => notifier.updatePreferences(
              profile.preferences.copyWith(
                preferWellLit: value,
                warnPoorLighting: value,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Audio'),
            subtitle: const Text(
              'Speaks directions and answers. Off means the app makes no sound.',
            ),
            value: profile.preferences.spokenInstructions,
            onChanged: (value) {
              notifier.updatePreferences(
                profile.preferences.copyWith(spokenInstructions: value),
              );
              if (!value) {
                ref.read(voiceServiceProvider).stopSpeaking();
              }
            },
          ),
          SwitchListTile(
            title: const Text('Haptic alerts'),
            value: profile.hapticAlerts,
            onChanged: notifier.setHaptics,
          ),
          SwitchListTile(
            title: const Text('Cycling mode'),
            value: profile.preferences.cyclistMode,
            onChanged: (value) => notifier.updatePreferences(
              profile.preferences.copyWith(cyclistMode: value),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Preferences are saved on this device. When you sign in under '
              'Settings → Account with sync enabled, they also save to your '
              'PathAble profile.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
