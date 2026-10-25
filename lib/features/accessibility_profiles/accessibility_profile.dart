import 'package:equatable/equatable.dart';

import '../../routing/routing_models.dart';

enum ProfilePreset {
  generalPedestrian,
  wheelchairMobility,
  blind,
  lowVision,
  cyclist,
  custom,
}

class AccessibilityProfile extends Equatable {
  const AccessibilityProfile({
    this.preset = ProfilePreset.generalPedestrian,
    this.preferences = const AccessibilityRoutingPreferences(
      avoidImpassableClosures: true,
    ),
    this.warningDistanceMeters = 40,
    this.hapticAlerts = false,
    this.speechRate = 0.5,
  });

  final ProfilePreset preset;
  final AccessibilityRoutingPreferences preferences;
  final double warningDistanceMeters;
  final bool hapticAlerts;
  final double speechRate;

  factory AccessibilityProfile.fromPreset(ProfilePreset preset) {
    return switch (preset) {
      ProfilePreset.generalPedestrian => const AccessibilityProfile(
          preset: ProfilePreset.generalPedestrian,
          preferences: AccessibilityRoutingPreferences(
            avoidImpassableClosures: true,
          ),
        ),
      ProfilePreset.wheelchairMobility => const AccessibilityProfile(
          preset: ProfilePreset.wheelchairMobility,
          preferences: AccessibilityRoutingPreferences(
            wheelchairMode: true,
            avoidStairs: true,
            avoidMissingCurbRamps: true,
            avoidImpassableClosures: true,
          ),
        ),
      ProfilePreset.blind => const AccessibilityProfile(
          preset: ProfilePreset.blind,
          preferences: AccessibilityRoutingPreferences(
            blindMode: true,
            lowVisionMode: true,
            spokenInstructions: true,
            avoidImpassableClosures: true,
            warnPoorLighting: true,
          ),
          hapticAlerts: true,
          warningDistanceMeters: 50,
        ),
      ProfilePreset.lowVision => const AccessibilityProfile(
          preset: ProfilePreset.lowVision,
          preferences: AccessibilityRoutingPreferences(
            lowVisionMode: true,
            spokenInstructions: true,
            avoidImpassableClosures: true,
            warnPoorLighting: true,
          ),
          hapticAlerts: true,
          warningDistanceMeters: 50,
        ),
      ProfilePreset.cyclist => const AccessibilityProfile(
          preset: ProfilePreset.cyclist,
          preferences: AccessibilityRoutingPreferences(
            cyclistMode: true,
            avoidImpassableClosures: true,
          ),
        ),
      ProfilePreset.custom => const AccessibilityProfile(
          preset: ProfilePreset.custom,
        ),
    };
  }

  AccessibilityProfile copyWith({
    ProfilePreset? preset,
    AccessibilityRoutingPreferences? preferences,
    double? warningDistanceMeters,
    bool? hapticAlerts,
    double? speechRate,
  }) {
    return AccessibilityProfile(
      preset: preset ?? this.preset,
      preferences: preferences ?? this.preferences,
      warningDistanceMeters:
          warningDistanceMeters ?? this.warningDistanceMeters,
      hapticAlerts: hapticAlerts ?? this.hapticAlerts,
      speechRate: speechRate ?? this.speechRate,
    );
  }

  String get label => switch (preset) {
        ProfilePreset.generalPedestrian => 'General pedestrian',
        ProfilePreset.wheelchairMobility => 'Wheelchair / mobility',
        ProfilePreset.blind => 'Blind',
        ProfilePreset.lowVision => 'Low vision',
        ProfilePreset.cyclist => 'Cyclist',
        ProfilePreset.custom => 'Custom combination',
      };

  Map<String, dynamic> toJson() => {
        'preset': preset.name,
        'preferences': {
          'wheelchairMode': preferences.wheelchairMode,
          'lowVisionMode': preferences.lowVisionMode,
          'blindMode': preferences.blindMode,
          'cyclistMode': preferences.cyclistMode,
          'avoidStairs': preferences.avoidStairs,
          'avoidMissingCurbRamps': preferences.avoidMissingCurbRamps,
          'avoidImpassableClosures': preferences.avoidImpassableClosures,
          'preferWellLit': preferences.preferWellLit,
          'spokenInstructions': preferences.spokenInstructions,
          'warnPoorLighting': preferences.warnPoorLighting,
        },
        'warningDistanceMeters': warningDistanceMeters,
        'hapticAlerts': hapticAlerts,
        'speechRate': speechRate,
      };

  factory AccessibilityProfile.fromJson(Map<String, dynamic> json) {
    final presetName = json['preset'] as String?;
    final preset = ProfilePreset.values.firstWhere(
      (value) => value.name == presetName,
      orElse: () => presetName == 'blindLowVision'
          ? ProfilePreset.blind
          : ProfilePreset.custom,
    );
    final prefs = json['preferences'] as Map<String, dynamic>? ?? const {};
    return AccessibilityProfile(
      preset: preset,
      preferences: AccessibilityRoutingPreferences(
        wheelchairMode: prefs['wheelchairMode'] as bool? ?? false,
        lowVisionMode: prefs['lowVisionMode'] as bool? ?? false,
        blindMode: prefs['blindMode'] as bool? ??
            (preset == ProfilePreset.blind || presetName == 'blindLowVision'),
        cyclistMode: prefs['cyclistMode'] as bool? ?? false,
        avoidStairs: prefs['avoidStairs'] as bool? ?? false,
        avoidMissingCurbRamps: prefs['avoidMissingCurbRamps'] as bool? ?? false,
        avoidImpassableClosures:
            prefs['avoidImpassableClosures'] as bool? ?? true,
        preferWellLit: prefs['preferWellLit'] as bool? ?? false,
        spokenInstructions: prefs['spokenInstructions'] as bool? ?? false,
        warnPoorLighting: prefs['warnPoorLighting'] as bool? ?? false,
      ),
      warningDistanceMeters:
          (json['warningDistanceMeters'] as num?)?.toDouble() ?? 40,
      hapticAlerts: json['hapticAlerts'] as bool? ?? false,
      speechRate: (json['speechRate'] as num?)?.toDouble() ?? 0.5,
    );
  }

  @override
  List<Object?> get props =>
      [preset, preferences, warningDistanceMeters, hapticAlerts, speechRate];
}
