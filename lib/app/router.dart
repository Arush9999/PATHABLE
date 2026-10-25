import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/accessibility_profiles/accessibility_profile_screen.dart';
import '../features/hazards/confirm_hazard_screen.dart';
import '../features/hazards/hazard_detail_screen.dart';
import '../features/map/map_screen.dart';
import '../features/navigation/active_navigation_screen.dart';
import '../features/navigation/route_preview_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/reporting/report_hazard_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/account_screen.dart';
import '../features/settings/settings_screen.dart';

abstract final class AppRoutes {
  static const onboarding = '/onboarding';
  static const map = '/';
  static const settings = '/settings';
  static const account = '/account';
  static const report = '/report';
  static const search = '/search';
  static const routePreview = '/route-preview';
  static const navigation = '/navigation';
  static const accessibility = '/accessibility';
  static const hazardDetail = '/hazards/:id';
  static const confirmHazard = '/hazards/:id/confirm';

  static String hazard(String id) => '/hazards/$id';

  static String confirm(String id) => '/hazards/$id/confirm';

  static String accountWithNext(String next) =>
      '$account?next=${Uri.encodeComponent(next)}';
}

GoRouter createAppRouter({
  bool showOnboarding = true,
  bool requireAccount = false,
  Listenable? authRefresh,
  bool Function()? isSignedIn,
}) {
  final signedIn = isSignedIn ?? () => false;

  return GoRouter(
    initialLocation: showOnboarding ? AppRoutes.onboarding : AppRoutes.map,
    refreshListenable: authRefresh,
    redirect: (context, state) {
      if (!requireAccount) return null;

      final loc = state.matchedLocation;
      final loggingIn = loc == AppRoutes.account;
      final onboarding = loc == AppRoutes.onboarding;
      final authed = signedIn();

      if (!authed && !loggingIn && !onboarding) {
        return AppRoutes.accountWithNext(state.uri.toString());
      }
      // Stay on Account when already signed in (profile management).
      // Post-login navigation is handled by AccountScreen via `next`.
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.map,
        name: 'map',
        builder: (context, state) => const MapScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.account,
        name: 'account',
        builder: (context, state) => const AccountScreen(),
      ),
      GoRoute(
        path: AppRoutes.report,
        name: 'report',
        builder: (context, state) => const ReportHazardScreen(),
      ),
      GoRoute(
        path: AppRoutes.search,
        name: 'search',
        builder: (context, state) {
          final forOrigin = state.uri.queryParameters['for'] == 'origin';
          return SearchScreen(
            pickTarget: forOrigin
                ? SearchPickTarget.origin
                : SearchPickTarget.destination,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.routePreview,
        name: 'routePreview',
        builder: (context, state) => const RoutePreviewScreen(),
      ),
      GoRoute(
        path: AppRoutes.navigation,
        name: 'navigation',
        builder: (context, state) => const ActiveNavigationScreen(),
      ),
      GoRoute(
        path: AppRoutes.accessibility,
        name: 'accessibility',
        builder: (context, state) => const AccessibilityProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.hazardDetail,
        name: 'hazardDetail',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return HazardDetailScreen(hazardId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.confirmHazard,
        name: 'confirmHazard',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ConfirmHazardScreen(hazardId: id);
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'That screen could not be found.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(AppRoutes.map),
                child: const Text('Return to map'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
