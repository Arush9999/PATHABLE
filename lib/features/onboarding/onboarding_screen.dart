import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/widgets/demo_banner.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _pages = [
    _OnboardingPage(
      title: 'PathAble',
      subtitle: 'Every path. Every person. Every step.',
      body:
          'Crowdsourced pedestrian navigation that accounts for accessibility '
          'needs and community-reported hazards on sidewalks, paths, and trails.',
      icon: Icons.accessible_forward,
    ),
    _OnboardingPage(
      title: 'Report what blocks the way',
      subtitle: 'Help your community',
      body:
          'Share blocked sidewalks, missing curb ramps, broken elevators, '
          'construction closures, and other hazards that affect travel.',
      icon: Icons.report_outlined,
    ),
    _OnboardingPage(
      title: 'Choose your preferences',
      subtitle: 'No diagnosis required',
      body:
          'Choose Blind, low vision, or a mobility profile. Audio speaks '
          'directions when you turn it on. Preferences stay on this device '
          'unless you sync them with your account.',
      icon: Icons.tune,
    ),
    _OnboardingPage(
      title: 'Your account',
      subtitle: 'Sign in to continue',
      body:
          'Create an account with email or Google so your reports and '
          'preferences stay with you. Directions stay on paths and sidewalks. '
          'If a path ends, they follow the sidewalk beside the road until '
          'the path resumes.',
      icon: Icons.person_outline,
    ),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (!mounted) return;
    final config = ref.read(appConfigurationProvider);
    if (config.requiresAccount) {
      context.go(AppRoutes.accountWithNext(AppRoutes.map));
    } else {
      context.go(AppRoutes.map);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = ref.watch(appConfigurationProvider);
    final pages = config.requiresAccount
        ? _pages
        : _pages.where((p) => p.title != 'Your account').toList();

    return Scaffold(
      body: Column(
        children: [
          if (config.isDemoMode) const DemoBanner(),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: pages.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, index) {
                final page = pages[index];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Spacer(),
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              theme.colorScheme.primary,
                              theme.colorScheme.secondary,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.24),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(
                          page.icon,
                          size: 36,
                          color: theme.colorScheme.onPrimary,
                          semanticLabel: page.title,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        page.title,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        page.subtitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.secondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        page.body,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.35,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.85),
                        ),
                      ),
                      const Spacer(flex: 2),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Semantics(
                  label: 'Page ${_index + 1} of ${pages.length}',
                  child: Row(
                    children: List.generate(pages.length, (i) {
                      return Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _index
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                        ),
                      );
                    }),
                  ),
                ),
                const Spacer(),
                if (_index < pages.length - 1)
                  FilledButton(
                    onPressed: () => _controller.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    ),
                    child: const Text('Next'),
                  )
                else
                  FilledButton(
                    onPressed: _finish,
                    child: Text(
                      config.requiresAccount
                          ? 'Continue to account'
                          : 'Enter the map',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage {
  const _OnboardingPage({
    required this.title,
    required this.subtitle,
    required this.body,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String body;
  final IconData icon;
}
