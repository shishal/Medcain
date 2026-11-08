import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/brand_assets.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/dusk_form_page.dart';
import '../../../../core/utils/auth_validators.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/utils/soft_keyboard.dart';
import '../../data/auth_repository.dart';
import '../providers/auth_session_provider.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _showPassword = false;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
        .signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

    if (!mounted) return;
    ref.read(authSessionProvider.notifier).syncWithClient();
    if (!mounted) return;

    setState(() => _isLoading = false);

    switch (result) {
      case Success(:final value):
        // Null value = email confirmation required (no session yet).
        if (value != null) {
          ref.read(deviceSessionNoticeProvider.notifier).setFromClaim(value);
          context.go(AppRoutes.home);
        } else {
          setState(
            () => _infoMessage =
                'Account created. Check your email to confirm, then log in.',
          );
        }
      case Failure(:final message):
        setState(() => _errorMessage = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DuskFormPage(
      formKey: _formKey,
      mascotAsset: BrandAssets.mascotStudy,
      title: 'Let’s start',
      subtitle:
          'Create an account to study PYQs with ${BrandAssets.mascotName}.',
      children: [
        if (_errorMessage != null) ...[
          Text(_errorMessage!, style: TextStyle(color: colorScheme.error)),
          const SizedBox(height: Spacing.md),
        ],
        if (_infoMessage != null) ...[
          Text(_infoMessage!, style: TextStyle(color: colorScheme.primary)),
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
              tooltip: _showPassword ? 'Hide password' : 'Show password',
              icon: Icon(
                _showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          obscureText: !_showPassword,
          keyboardType: TextInputType.visiblePassword,
          autofillHints: const [AutofillHints.newPassword],
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
              : const Text('Create account'),
        ),
        const SizedBox(height: Spacing.md),
        TextButton(
          onPressed: _isLoading ? null : () => context.go(AppRoutes.login),
          child: const Text('Already have an account? Log in'),
        ),
      ],
    );
  }
}
