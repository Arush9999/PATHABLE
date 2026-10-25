import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../backend/supabase_client.dart';
import '../data/services/pending_report_flusher.dart';
import 'auth_refresh.dart';
import 'providers.dart';
import 'router.dart';
import 'theme.dart';

class PathAbleApp extends ConsumerStatefulWidget {
  const PathAbleApp({
    super.key,
    this.showOnboarding = true,
  });

  final bool showOnboarding;

  @override
  ConsumerState<PathAbleApp> createState() => _PathAbleAppState();
}

class _PathAbleAppState extends ConsumerState<PathAbleApp> {
  late final AuthRefresh _authRefresh;
  late final GoRouter _router;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<dynamic>? _authSub;

  @override
  void initState() {
    super.initState();
    final config = ref.read(appConfigurationProvider);
    _authRefresh = AuthRefresh();
    _router = createAppRouter(
      showOnboarding: widget.showOnboarding,
      requireAccount: config.requiresAccount,
      authRefresh: _authRefresh,
      isSignedIn: () {
        if (!PathAbleSupabase.isInitialized) return false;
        return PathAbleSupabase.client.auth.currentSession != null;
      },
    );

    if (PathAbleSupabase.isInitialized) {
      _authSub = PathAbleSupabase.client.auth.onAuthStateChange.listen((_) {
        _authRefresh.notify();
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(accessibilityProfileProvider.notifier).pullRemote();
      _flushPendingReports();
      _connectivitySub = Connectivity().onConnectivityChanged.listen((_) {
        _flushPendingReports();
      });
    });
  }

  Future<void> _flushPendingReports() async {
    final config = ref.read(appConfigurationProvider);
    if (config.isDemoMode || !PathAbleSupabase.isInitialized) return;
    if (PathAbleSupabase.client.auth.currentSession == null) return;
    final prefs = ref.read(sharedPreferencesProvider);
    final repo = ref.read(hazardRepositoryProvider);
    final flushed = await PendingReportFlusher(
      prefs: prefs,
      repository: repo,
    ).flush();
    if (flushed > 0) {
      ref.invalidate(nearbyHazardsProvider);
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _authSub?.cancel();
    _authRefresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(userLocationProvider, (previous, next) {
      final point = next.asData?.value;
      if (point == null) return;
      ref.read(passageTrackerProvider).onFix(point).then((changed) {
        if (changed) ref.invalidate(nearbyHazardsProvider);
      });
    });

    final darkMode = ref.watch(darkModeProvider);

    return MaterialApp.router(
      title: 'PathAble',
      debugShowCheckedModeBanner: false,
      theme: PathAbleTheme.light(),
      darkTheme: PathAbleTheme.dark(),
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      routerConfig: _router,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        // Respect system text scaling; clamp extreme values for layout safety.
        final scale = media.textScaler.scale(1).clamp(0.9, 2.0);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
