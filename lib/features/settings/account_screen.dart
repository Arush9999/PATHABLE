import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/widgets/demo_banner.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/user_profile_service.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  bool _busy = false;
  bool _syncEnabled = true;
  String? _message;
  bool _messageIsError = true;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    final params = Uri.base.queryParameters;
    final description = params['error_description'] ?? params['error'];
    if (description == null || description.isEmpty) return;
    _message = describeAuthFailure(description, isWeb: true);
    _messageIsError = true;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _afterSignedIn() async {
    try {
      await ref
          .read(accessibilityProfileProvider.notifier)
          .pullRemote()
          .timeout(const Duration(seconds: 8));
    } catch (error, stack) {
      debugPrint('Profile sync after sign-in skipped: $error\n$stack');
    }
    final profile = const UserProfileService();
    final name = profile.displayName;
    if (name != null && name.isNotEmpty) {
      _displayName.text = name;
    }
    if (!mounted) return;
    final next = GoRouterState.of(context).uri.queryParameters['next'];
    if (next != null && next.isNotEmpty) {
      context.go(next);
      return;
    }
    context.go(AppRoutes.map);
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(authServiceProvider).signInWithEmail(
            email: _email.text,
            password: _password.text,
          );
      await _afterSignedIn();
    } catch (error) {
      _showError(describeAuthFailure(error, isWeb: kIsWeb));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signUp() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final response = await ref.read(authServiceProvider).signUpWithEmail(
            email: _email.text,
            password: _password.text,
            displayName: _displayName.text,
          );
      if (response.session != null) {
        await ref.read(accessibilityProfileProvider.notifier).pushRemote(
              syncEnabled: _syncEnabled,
            );
        await _afterSignedIn();
      } else if (mounted) {
        setState(() {
          _messageIsError = false;
          _message =
              'Account created. Confirm your email if required, then sign in.';
        });
      }
    } catch (error) {
      _showError(describeAuthFailure(error, isWeb: kIsWeb));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final response = await ref.read(authServiceProvider).signInWithGoogle();
      if (!mounted) return;
      if (response == null) {
        final redirect = webAuthRedirect();
        setState(() {
          _messageIsError = false;
          _message = redirect == null
              ? 'Opening Google sign-in…'
              : 'Opening Google sign-in. If this page stays here, add '
                  '$redirect to Supabase redirect URLs.';
        });
        return;
      }
      await _afterSignedIn();
    } catch (error) {
      _showError(describeAuthFailure(error, isWeb: kIsWeb));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = true;
    });
  }

  Future<void> _signOut() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(authServiceProvider).signOut();
      if (!mounted) return;
      setState(() {
        _messageIsError = false;
        _message = 'Signed out.';
      });
    } catch (error) {
      _showError(describeAuthFailure(error, isWeb: kIsWeb));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final service = const UserProfileService();
      await service.updateDisplayName(_displayName.text);
      await ref.read(accessibilityProfileProvider.notifier).pushRemote(
            syncEnabled: _syncEnabled,
          );
      if (!mounted) return;
      setState(() {
        _messageIsError = false;
        _message = 'Profile saved.';
      });
    } catch (error) {
      _showError(describeAuthFailure(error, isWeb: kIsWeb));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigurationProvider);
    final authAsync = ref.watch(authSessionProvider);
    final session = authAsync.value;
    final profile = ref.watch(accessibilityProfileProvider);
    final googleReady = config.hasGoogleSignIn;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    if (session != null && _displayName.text.isEmpty && !_busy) {
      final name = const UserProfileService().displayName;
      if (name != null && name.isNotEmpty) {
        _displayName.text = name;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (config.isDemoMode)
            const DemoBanner(
              message:
                  'Demo mode — connect Supabase in .env to enable real accounts.',
            ),
          if (!config.hasSupabase)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Accounts need SUPABASE_URL and SUPABASE_ANON_KEY in .env. '
                'Add GOOGLE_WEB_CLIENT_ID to enable Google Sign-In.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          if (session != null) ...[
            Text(
              'Signed in',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(session.user.email ?? session.user.id),
            const SizedBox(height: 16),
            TextField(
              controller: _displayName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Display name',
                hintText: 'How you appear in PathAble',
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sync accessibility preferences'),
              subtitle: Text('Current: ${profile.label}'),
              value: _syncEnabled,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _syncEnabled = value),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _saveProfile,
              child: const Text('Save profile'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => context.push(AppRoutes.accessibility),
              child: const Text('Edit accessibility preferences'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _signOut,
              child: const Text('Sign out'),
            ),
          ] else ...[
            Text(
              config.requiresAccount
                  ? 'Sign in or create an account to use PathAble. '
                      'Reports and directions sync to your account.'
                  : 'Create an account to sync accessibility preferences '
                      'and submit hazard reports when connected.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            if (config.hasSupabase && googleReady) ...[
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _signInWithGoogle,
                icon: const Icon(Icons.g_mobiledata, size: 28),
                label: const Text('Continue with Google'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or email',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),
            ] else if (config.hasSupabase && !googleReady) ...[
              Text(
                'Google Sign-In activates when GOOGLE_WEB_CLIENT_ID is set in .env.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _displayName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Display name (optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              enabled: config.hasSupabase && !_busy,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              enabled: config.hasSupabase && !_busy,
              onSubmitted: (_) {
                if (!_busy && config.hasSupabase) unawaited(_signIn());
              },
              decoration: const InputDecoration(
                labelText: 'Password',
                helperText: 'At least 6 characters',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: (!_busy && config.hasSupabase) ? _signIn : null,
              child: _busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: onPrimary,
                      ),
                    )
                  : const Text('Sign in'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: (!_busy && config.hasSupabase) ? _signUp : null,
              child: const Text('Create account'),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(
              _message!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _messageIsError
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
