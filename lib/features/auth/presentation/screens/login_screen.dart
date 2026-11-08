import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/brand_assets.dart';
import '../../../../core/theme/brand_identity.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/auth_validators.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/utils/soft_keyboard.dart';
import '../../../../core/widgets/brand_wordmark.dart';
import '../../../../core/widgets/comic_mascot.dart';
import '../../../profile/presentation/providers/user_profile_provider.dart';
import '../../data/auth_repository.dart';
import '../../domain/device_session.dart';
import '../providers/auth_session_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _showPassword = false;
  String? _errorMessage;
  String? _infoMessage;
  var _consumedQueryReason = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_consumedQueryReason) return;
    _consumedQueryReason = true;

    String? reason;
    // Login is usually under GoRouter; widget tests may mount it alone.
    try {
      reason = GoRouterState.of(context).uri.queryParameters['reason'];
    } on Object {
      reason = null;
    }

    final fromQuery = switch (reason) {
      AppRoutes.loginReasonOtherDevice =>
        DeviceSessionMessages.signedInElsewhere,
      AppRoutes.loginReasonPlanSuspended =>
        DeviceSessionMessages.planSuspended,
      AppRoutes.loginReasonDeviceLimit => DeviceSessionMessages.deviceLimit,
      _ => null,
    };

    final fromNotice = ref.read(deviceSessionNoticeProvider);
    if (fromNotice != null) {
      // didChangeDependencies runs while the tree is building. Clearing the
      // notice now would notify listeners mid-frame, which Riverpod rejects.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(deviceSessionNoticeProvider.notifier).clear();
      });
    }

    final message = fromQuery ?? fromNotice;
    if (message != null) {
      _infoMessage = message;
    }
  }

  Future<void> _submit() async {
    setState(() {
      _errorMessage = null;
      _infoMessage = null;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    final result = await ref
        .read(authRepositoryProvider)
        .signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

    if (!mounted) return;
    // Claim finished (and may have signed out). Publish that result
    // before navigating so the router does not open the splash screen.
    ref.read(authSessionProvider.notifier).syncWithClient();
    if (!mounted) return;

    setState(() => _isLoading = false);

    switch (result) {
      case Success(:final value):
        ref.read(deviceSessionNoticeProvider.notifier).setFromClaim(value);
        if (value.justSuspended) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(DeviceSessionMessages.planSuspended)),
          );
        }
        var isAdmin = false;
        try {
          isAdmin =
              (await ref.read(userProfileProvider.future))?.isAdmin ?? false;
        } catch (_) {
          isAdmin = false;
        }
        if (!mounted) return;
        context.go(isAdmin ? AppRoutes.admin : AppRoutes.home);
      case Failure(:final message):
        setState(() => _errorMessage = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const SizedBox(height: Spacing.lg),
                const Center(
                  child: BrandWordmark(
                    markSize: 40,
                    showTagline: true,
                    alignment: MainAxisAlignment.center,
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                const Center(
                  child: ComicMascot(
                    asset: BrandAssets.mascotWave,
                    size: 120,
                    heroTag: BrandAssets.mascotHeroTag,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Text(
                  'Welcome back',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'Sign in to keep studying with ${BrandIdentity.displayName}.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.xl),
                if (_infoMessage != null) ...[
                  Text(
                    _infoMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                ],
                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                ],
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  stylusHandwritingEnabled: false,
                  onTap: requestSoftKeyboard,
                  enabled: !_isLoading,
                  validator: AuthValidators.email,
                ),
                const SizedBox(height: Spacing.md),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      tooltip: _showPassword
                          ? 'Hide password'
                          : 'Show password',
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  obscureText: !_showPassword,
                  keyboardType: TextInputType.visiblePassword,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  stylusHandwritingEnabled: false,
                  onTap: requestSoftKeyboard,
                  enabled: !_isLoading,
                  onFieldSubmitted: (_) => _submit(),
                  validator: AuthValidators.password,
                ),
                const SizedBox(height: Spacing.xl),
                FilledButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign in'),
                ),
                const SizedBox(height: Spacing.md),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => context.go(AppRoutes.signup),
                  child: const Text('Create an account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
