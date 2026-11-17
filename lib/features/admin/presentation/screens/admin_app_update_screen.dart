import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/result.dart';
import '../../../app_update/data/app_update_repository.dart';
import '../../data/admin_repository.dart';

/// Sets the minimum Android build that may open the app.
class AdminAppUpdateScreen extends ConsumerStatefulWidget {
  const AdminAppUpdateScreen({super.key});

  @override
  ConsumerState<AdminAppUpdateScreen> createState() =>
      _AdminAppUpdateScreenState();
}

class _AdminAppUpdateScreenState extends ConsumerState<AdminAppUpdateScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  var _loading = true;
  var _busy = false;
  String? _error;
  String? _savedNote;
  InstalledBuild? _installed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final policy = await ref.read(adminRepositoryProvider).getAppUpdatePolicy();
    InstalledBuild? installed;
    try {
      installed = await ref.read(appUpdateRepositoryProvider).installedBuild();
    } catch (_) {
      installed = null;
    }
    if (!mounted) return;
    switch (policy) {
      case Success(:final value):
        _code.text = '${value.minVersionCode}';
        _name.text = value.minVersionName;
        setState(() {
          _installed = installed;
          _loading = false;
        });
      case Failure(:final message):
        setState(() {
          _installed = installed;
          _error = message;
          _loading = false;
        });
    }
  }

  Future<void> _save() async {
    final code = int.tryParse(_code.text.trim());
    if (code == null || code < 0) {
      setState(() {
        _error = 'Enter a build number, or 0 to allow every version.';
      });
      return;
    }

    final installedCode = _installed?.versionCode;
    if (installedCode != null && code > installedCode) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Lock this phone too?'),
          content: Text(
            'This phone is build $installedCode. After you save $code, '
            'it will also stop on the update screen until that build is installed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _savedNote = null;
    });
    final result = await ref
        .read(adminRepositoryProvider)
        .setAppUpdatePolicy(
          minVersionCode: code,
          minVersionName: _name.text.trim(),
        );
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        _code.text = '${value.minVersionCode}';
        _name.text = value.minVersionName;
        setState(() {
          _busy = false;
          _savedNote = value.isEnforced
              ? 'Builds below ${value.minVersionCode} must update.'
              : 'Every installed build can open the app.';
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
    final installed = _installed;
    return Scaffold(
      appBar: AppBar(title: const Text('App update')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(Spacing.md),
              children: [
                Text(
                  installed == null
                      ? 'The minimum is the Android build number, the integer after + in pubspec.yaml.'
                      : 'This phone is ${installed.label}. The minimum is that build number, the integer after + in pubspec.yaml.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.md),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.md),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_savedNote != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.md),
                    child: Text(_savedNote!),
                  ),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Minimum build number',
                    hintText: '0',
                    helperText: 'Phones below this number must update. 0 allows every build.',
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Version name shown to students',
                    hintText: '1.1.26',
                    helperText: 'Optional. Example: 1.1.26',
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Text(
                  'Publish the build to the Play Store first, then enter its build number. The button on the lock screen opens this app’s Play listing. The website admin stays available if this phone gets locked.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: Spacing.md),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Save'),
                ),
              ],
            ),
    );
  }
}
