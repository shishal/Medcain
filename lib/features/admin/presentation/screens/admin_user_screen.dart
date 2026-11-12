import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/result.dart';
import '../../../catalog/data/catalog_repository.dart';
import '../../../catalog/domain/catalog_models.dart';
import '../../data/admin_repository.dart';
import '../../domain/admin_models.dart';
import '../widgets/admin_choice.dart';

class AdminUserScreen extends ConsumerStatefulWidget {
  const AdminUserScreen({required this.userId, super.key});

  final String userId;

  @override
  ConsumerState<AdminUserScreen> createState() => _AdminUserScreenState();
}

class _AdminUserScreenState extends ConsumerState<AdminUserScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _batch = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordAgain = TextEditingController();
  final _blockReason = TextEditingController();

  AdminUser? _user;
  List<University> _universities = const [];
  List<College> _colleges = const [];
  List<MbbsPhase> _phases = const [];
  String? _universityId;
  String? _collegeId;
  String? _phaseId;
  String _plan = '';
  List<(String, String)> _plans = const [];
  List<(String, String, bool)> _planRows = const [];
  DateTime? _expires;
  var _loading = true;
  var _busy = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _batch.dispose();
    _email.dispose();
    _password.dispose();
    _passwordAgain.dispose();
    _blockReason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = ref.read(adminRepositoryProvider);
    final catalog = ref.read(catalogRepositoryProvider);
    final userResult = await repo.getUser(widget.userId);
    final planResult = await repo.listAssignablePlans();
    final universities = await catalog.fetchUniversities();
    final phases = await catalog.fetchPhases();
    if (!mounted) return;

    final failure = switch (userResult) {
      Failure(:final message) => message,
      Success() => null,
    };
    if (failure != null) {
      setState(() {
        _error = failure;
        _loading = false;
      });
      return;
    }

    final user = (userResult as Success<AdminUser>).value;
    List<College> colleges = const [];
    if (user.universityId != null) {
      final collegeResult = await catalog.fetchColleges(user.universityId!);
      if (collegeResult case Success(:final value)) colleges = value;
    }
    if (!mounted) return;

    _applyUser(user);
    setState(() {
      _universities = switch (universities) {
        Success(:final value) => value,
        Failure() => const [],
      };
      _phases = switch (phases) {
        Success(:final value) => value,
        Failure() => const [],
      };
      _colleges = colleges;
      _planRows = switch (planResult) {
        Success(:final value) => value,
        Failure() => const [],
      };
      _plans = [
        for (final row in _planRows)
          if (row.$3 || row.$1 == _plan) (row.$1, row.$2),
      ];
      _loading = false;
    });
  }

  void _applyUser(AdminUser user) {
    _user = user;
    _name.text = user.fullName ?? '';
    _phone.text = user.phone ?? '';
    _batch.text = user.batchYear?.toString() ?? '';
    _email.text = user.email;
    _universityId = user.universityId;
    _collegeId = user.collegeId;
    _phaseId = user.mbbsPhaseId;
    _plan = user.planId ?? '';
    _expires = user.planExpiresAt?.toLocal();
    _blockReason.text = user.blockedReason ?? '';
  }

  Future<void> _onUniversity(String? id) async {
    setState(() {
      _universityId = id;
      _collegeId = null;
      _colleges = const [];
    });
    if (id == null) return;
    final result = await ref.read(catalogRepositoryProvider).fetchColleges(id);
    if (!mounted) return;
    if (result case Success(:final value)) {
      setState(() => _colleges = value);
    }
  }

  Future<void> _saveProfile() async {
    final batchText = _batch.text.trim();
    int? batch;
    if (batchText.isNotEmpty) {
      batch = int.tryParse(batchText);
      if (batch == null) {
        setState(() => _error = 'Batch year must be a number.');
        return;
      }
    }
    await _run(() async {
      final result = await ref
          .read(adminRepositoryProvider)
          .updateProfile(
            AdminProfileInput(
              userId: widget.userId,
              fullName: _blankToNull(_name.text),
              phone: _blankToNull(_phone.text),
              universityId: _universityId,
              collegeId: _collegeId,
              batchYear: batch,
              mbbsPhaseId: _phaseId,
            ),
          );
      if (result case Success(:final value)) _applyUser(value);
      return result;
    }, 'Profile saved.');
  }

  Future<void> _savePlan() async {
    if (_plan.isEmpty) {
      setState(() => _error = 'Pick a plan.');
      return;
    }
    await _run(() async {
      final result = await ref
          .read(adminRepositoryProvider)
          .setPlan(userId: widget.userId, plan: _plan, expiresAt: _expires);
      if (result case Success(:final value)) _applyUser(value);
      return result;
    }, 'Plan saved.');
  }

  Future<void> _clearSuspension() async {
    await _run(() async {
      final result = await ref
          .read(adminRepositoryProvider)
          .clearDeviceSuspension(widget.userId);
      if (result case Success(:final value)) _applyUser(value);
      return result;
    }, 'Device suspension cleared.');
  }

  Future<void> _saveEmail() async {
    await _run(
      () => ref
          .read(adminRepositoryProvider)
          .setEmail(userId: widget.userId, email: _email.text),
      'Email updated.',
    );
  }

  Future<void> _savePassword() async {
    if (_password.text != _passwordAgain.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    await _run(
      () => ref
          .read(adminRepositoryProvider)
          .setPassword(userId: widget.userId, password: _password.text),
      'Password reset.',
    );
    if (mounted) {
      _password.clear();
      _passwordAgain.clear();
    }
  }

  Future<void> _toggleBlock() async {
    final user = _user;
    if (user == null) return;
    final blocking = !user.isBlocked;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(blocking ? 'Block this user?' : 'Unblock this user?'),
        content: Text(
          blocking
              ? 'They will be signed out and cannot sign in until you unblock them.'
              : 'They will be able to sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(blocking ? 'Block' : 'Unblock'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      final result = await ref
          .read(adminRepositoryProvider)
          .setBlocked(
            userId: widget.userId,
            blocked: blocking,
            reason: _blockReason.text,
          );
      if (result is Success) {
        final refreshed = await ref
            .read(adminRepositoryProvider)
            .getUser(widget.userId);
        if (refreshed case Success(:final value)) _applyUser(value);
      }
      return result;
    }, blocking ? 'User blocked.' : 'User unblocked.');
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expires ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 15),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _expires = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
    });
  }

  Future<void> _run<T>(Future<Result<T>> Function() action, String ok) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    final result = await action();
    if (!mounted) return;
    switch (result) {
      case Success():
        setState(() {
          _busy = false;
          _notice = ok;
        });
      case Failure(:final message):
        setState(() {
          _busy = false;
          _error = message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final user = _user;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('User')),
        body: Center(child: Text(_error ?? 'User not found.')),
      );
    }

    final expiryLabel = _expires == null
        ? 'No expiry'
        : '${_expires!.year}-${_expires!.month.toString().padLeft(2, '0')}-${_expires!.day.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(title: Text(user.displayName)),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          if (_error != null) _Banner(text: _error!, isError: true),
          if (_notice != null) _Banner(text: _notice!, isError: false),
          Text(user.contactLabel, style: Theme.of(context).textTheme.titleMedium),
          if (user.isAdmin) const Text('This account is an admin.'),
          const SizedBox(height: Spacing.md),
          Text('Profile', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Phone'),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: Spacing.sm),
          AdminChoice(
            label: 'University',
            value: _universityId,
            allowEmpty: true,
            emptyLabel: 'None',
            items: [
              for (final university in _universities)
                (university.id, '${university.code} · ${university.name}'),
            ],
            onChanged: _busy ? (_) {} : _onUniversity,
          ),
          const SizedBox(height: Spacing.sm),
          AdminChoice(
            label: 'College',
            value: _collegeId,
            allowEmpty: true,
            items: [
              for (final college in _colleges) (college.id, college.label),
            ],
            onChanged: _busy ? (_) {} : (id) => setState(() => _collegeId = id),
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _batch,
            decoration: const InputDecoration(labelText: 'Batch year'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: Spacing.sm),
          AdminChoice(
            label: 'MBBS phase',
            value: _phaseId,
            allowEmpty: true,
            items: [for (final phase in _phases) (phase.id, phase.name)],
            onChanged: _busy ? (_) {} : (id) => setState(() => _phaseId = id),
          ),
          const SizedBox(height: Spacing.sm),
          FilledButton(
            onPressed: _busy ? null : _saveProfile,
            child: const Text('Save profile'),
          ),
          const SizedBox(height: Spacing.lg),
          Text('Plan', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Spacing.sm),
          AdminChoice(
            label: 'Plan',
            value: _plan,
            items: _plans,
            onChanged: _busy
                ? (_) {}
                : (id) => setState(() => _plan = id ?? ''),
          ),
          const SizedBox(height: Spacing.sm),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Expiry'),
            subtitle: Text(expiryLabel),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: _busy ? null : _pickExpiry,
          ),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _expires = null),
            child: const Text('Clear expiry'),
          ),
          FilledButton(
            onPressed: _busy ? null : _savePlan,
            child: const Text('Save plan'),
          ),
          if (user.planSuspendedAt != null) ...[
            const SizedBox(height: Spacing.sm),
            OutlinedButton(
              onPressed: _busy ? null : _clearSuspension,
              child: const Text('Clear device suspension'),
            ),
          ],
          if (user.email.isEmpty) ...[
            const SizedBox(height: Spacing.lg),
            Text('Sign-in', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            const Text(
              'This account signs in with WhatsApp. There is no password.',
            ),
          ] else ...[
            const SizedBox(height: Spacing.lg),
            Text('Credentials', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy ? null : _saveEmail,
                child: const Text('Update email'),
              ),
            ),
            TextField(
              controller: _password,
              decoration: const InputDecoration(labelText: 'New password'),
              obscureText: true,
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _passwordAgain,
              decoration: const InputDecoration(labelText: 'Confirm password'),
              obscureText: true,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy ? null : _savePassword,
                child: const Text('Reset password'),
              ),
            ),
          ],
          const SizedBox(height: Spacing.lg),
          Text('Access', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _blockReason,
            decoration: const InputDecoration(labelText: 'Block reason'),
          ),
          const SizedBox(height: Spacing.sm),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: user.isBlocked
                  ? null
                  : Theme.of(context).colorScheme.error,
            ),
            onPressed: _busy ? null : _toggleBlock,
            child: Text(user.isBlocked ? 'Unblock user' : 'Block user'),
          ),
          const SizedBox(height: Spacing.xl),
        ],
      ),
    );
  }
}

String? _blankToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Text(
        text,
        style: TextStyle(color: isError ? scheme.error : scheme.primary),
      ),
    );
  }
}
