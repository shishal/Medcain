import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/brand_assets.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/utils/soft_keyboard.dart';
import '../../../../core/utils/user_facing_error.dart';
import '../../../../core/widgets/brand_wordmark.dart';
import '../../../../core/widgets/comic_mascot.dart';
import '../../../profile/presentation/providers/user_profile_provider.dart';
import '../../data/auth_repository.dart';
import '../../domain/device_session.dart';
import '../../domain/whatsapp_challenge.dart';
import '../../domain/whatsapp_phone.dart';
import '../providers/auth_session_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();

  bool _isLoading = false;
  bool _pollInFlight = false;
  bool _finished = false;
  String? _errorMessage;
  String? _infoMessage;
  WhatsAppChallenge? _challenge;
  Timer? _pollTimer;
  var _consumedQueryReason = false;

  @override
  void initState() {
    super.initState();
    // WhatsApp is another app. When the student comes back we check at once
    // instead of waiting for the next timer tick.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pollOnce();
    }
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
      ref.read(deviceSessionNoticeProvider.notifier).clear();
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

    if (!_formKey.currentState!.validate()) return;

    final phone = WhatsAppPhone.normalize(_phoneController.text);
    if (phone == null) return;

    setState(() => _isLoading = true);

    final result = await ref
        .read(authRepositoryProvider)
        .startWhatsAppSignIn(phone: phone);

    if (!mounted) return;

    switch (result) {
      case Success(:final value):
        setState(() {
          _isLoading = false;
          _finished = false;
          _challenge = value;
        });
        _startPolling();
        await _openWhatsApp();
      case Failure(:final message):
        setState(() {
          _isLoading = false;
          _errorMessage = message;
        });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    // Timer.periodic keeps firing until we cancel it in dispose or when
    // sign-in finishes, so a closed screen never calls setState.
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollOnce(),
    );
  }

  Future<void> _pollOnce() async {
    final challenge = _challenge;
    if (challenge == null || _pollInFlight || _finished || !mounted) return;
    if (DateTime.now().isAfter(challenge.expiresAt)) {
      _failWaiting('That sign-in request expired. Try again.');
      return;
    }

    _pollInFlight = true;
    try {
      final result = await ref
          .read(authRepositoryProvider)
          .finishWhatsAppSignIn(
            challengeId: challenge.challengeId,
            secret: challenge.secret,
          );
      if (!mounted || _challenge?.challengeId != challenge.challengeId) return;

      switch (result) {
        case Success(:final value):
          if (value == null) return;
          _finished = true;
          _pollTimer?.cancel();
          await _enterApp(value);
        case Failure(:final message):
          if (message == UserFacingError.offlineMessage) {
            setState(() => _infoMessage = message);
            return;
          }
          _failWaiting(message);
      }
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> _enterApp(ClaimActiveDeviceResult value) async {
    ref.read(deviceSessionNoticeProvider.notifier).setFromClaim(value);
    if (value.justSuspended && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(DeviceSessionMessages.planSuspended)),
      );
    }
    var isAdmin = false;
    try {
      isAdmin = (await ref.read(userProfileProvider.future))?.isAdmin ?? false;
    } catch (_) {
      isAdmin = false;
    }
    if (!mounted) return;
    context.go(isAdmin ? AppRoutes.admin : AppRoutes.home);
  }

  void _failWaiting(String message) {
    _pollTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _challenge = null;
      _finished = false;
      _errorMessage = message;
      _infoMessage = null;
      _isLoading = false;
    });
  }

  void _useDifferentNumber() {
    _pollTimer?.cancel();
    setState(() {
      _challenge = null;
      _finished = false;
      _errorMessage = null;
      _infoMessage = null;
    });
  }

  Future<void> _openWhatsApp() async {
    final challenge = _challenge;
    if (challenge == null) return;
    final opened = await launchUrl(
      Uri.parse(challenge.waUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      setState(() {
        _errorMessage =
            'WhatsApp did not open. Copy the message and send it yourself.';
      });
    }
  }

  Future<void> _copyMessage() async {
    final message = _challenge?.message;
    if (message == null) return;
    await Clipboard.setData(ClipboardData(text: message));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _challenge != null;
    final colorScheme = Theme.of(context).colorScheme;

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
                  waiting ? 'Send the message' : 'Sign in with WhatsApp',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  waiting
                      ? 'Tap send in WhatsApp. Don\'t edit the message. We sign you in when it arrives.'
                      : 'New here? This creates your account too. You send the message — we never text you a code.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.xl),
                if (_infoMessage != null) ...[
                  Text(
                    _infoMessage!,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Spacing.md),
                ],
                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: colorScheme.error),
                  ),
                  const SizedBox(height: Spacing.md),
                ],
                if (!waiting) ...[
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'WhatsApp number',
                      hintText: '9876543210',
                    ),
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    textInputAction: TextInputAction.done,
                    stylusHandwritingEnabled: false,
                    onTap: requestSoftKeyboard,
                    enabled: !_isLoading,
                    onFieldSubmitted: (_) => _submit(),
                    validator: WhatsAppPhone.validator,
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
                        : const Text('Continue with WhatsApp'),
                  ),
                ] else ...[
                  Text(
                    _challenge!.phone,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: Spacing.md),
                  SelectableText(
                    _challenge!.message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  const Center(
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    'Waiting for your message…',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.xl),
                  FilledButton(
                    onPressed: _openWhatsApp,
                    child: const Text('Open WhatsApp'),
                  ),
                  const SizedBox(height: Spacing.sm),
                  TextButton(
                    onPressed: _copyMessage,
                    child: const Text('Copy message'),
                  ),
                  TextButton(
                    onPressed: _useDifferentNumber,
                    child: const Text('Use a different number'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
