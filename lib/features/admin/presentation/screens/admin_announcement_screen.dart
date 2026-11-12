import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/result.dart';
import '../../data/admin_repository.dart';
import '../../domain/admin_models.dart';
import '../widgets/admin_choice.dart';

class AdminAnnouncementScreen extends ConsumerStatefulWidget {
  const AdminAnnouncementScreen({this.announcementId, super.key});

  /// Null creates a draft. Otherwise loads that row from the admin list.
  final String? announcementId;

  @override
  ConsumerState<AdminAnnouncementScreen> createState() =>
      _AdminAnnouncementScreenState();
}

class _AdminAnnouncementScreenState
    extends ConsumerState<AdminAnnouncementScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _deepLink = TextEditingController();
  String _category = 'general';
  var _publish = false;
  DateTime? _expires;
  var _loading = false;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.announcementId != null) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _deepLink.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await ref.read(adminRepositoryProvider).listAnnouncements();
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        AdminAnnouncement? match;
        for (final item in value) {
          if (item.id == widget.announcementId) match = item;
        }
        if (match == null) {
          setState(() {
            _error = 'Notification not found.';
            _loading = false;
          });
          return;
        }
        _title.text = match.title;
        _body.text = match.body;
        _deepLink.text = match.deepLink ?? '';
        _category = match.category;
        _publish = match.isActive;
        _expires = match.expiresAt?.toLocal();
        setState(() => _loading = false);
      case Failure(:final message):
        setState(() {
          _error = message;
          _loading = false;
        });
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(adminRepositoryProvider)
        .upsertAnnouncement(
          AdminAnnouncementInput(
            id: widget.announcementId,
            title: _title.text.trim(),
            body: _body.text.trim(),
            category: _category,
            deepLink: _deepLink.text.trim().isEmpty
                ? null
                : _deepLink.text.trim(),
            isActive: _publish,
            expiresAt: _expires,
          ),
        );
    if (!mounted) return;
    switch (result) {
      case Success():
        context.pop();
      case Failure(:final message):
        setState(() {
          _busy = false;
          _error = message;
        });
    }
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expires ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _expires = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.announcementId == null ? 'New notification' : 'Notification',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(Spacing.md),
              children: [
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
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: Spacing.sm),
                TextField(
                  controller: _body,
                  decoration: const InputDecoration(labelText: 'Body'),
                  minLines: 4,
                  maxLines: 10,
                ),
                const SizedBox(height: Spacing.sm),
                AdminChoice(
                  label: 'Category',
                  value: _category,
                  items: adminAnnouncementCategories,
                  onChanged: (value) =>
                      setState(() => _category = value ?? 'general'),
                ),
                const SizedBox(height: Spacing.sm),
                TextField(
                  controller: _deepLink,
                  decoration: const InputDecoration(
                    labelText: 'App path (optional)',
                    hintText: '/upgrade',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Publish'),
                  subtitle: const Text(
                    'Students see published messages on the next Home load.',
                  ),
                  value: _publish,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _publish = value),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Expires'),
                  subtitle: Text(
                    _expires == null
                        ? 'Does not expire'
                        : _expires!.toLocal().toString().split(' ').first,
                  ),
                  trailing: const Icon(Icons.event_outlined),
                  onTap: _busy ? null : _pickExpiry,
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _expires = null),
                  child: const Text('Clear expiry'),
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
