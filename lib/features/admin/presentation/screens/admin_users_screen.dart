import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/result.dart';
import '../../data/admin_repository.dart';
import '../../domain/admin_models.dart';

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  final _query = TextEditingController();
  var _loading = false;
  String? _error;
  List<AdminUser> _users = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ref
        .read(adminRepositoryProvider)
        .searchUsers(_query.text);
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        setState(() {
          _users = value;
          _loading = false;
        });
      case Failure(:final message):
        setState(() {
          _error = message;
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    decoration: const InputDecoration(
                      labelText: 'Name or phone',
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                IconButton(
                  tooltip: 'Search',
                  onPressed: _loading ? null : _search,
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      return ListTile(
                        title: Text(user.displayName),
                        subtitle: Text(
                          [
                            user.contactLabel,
                            user.plan,
                            if (user.isBlocked) 'blocked',
                            if (user.planSuspendedAt != null) 'suspended',
                          ].join(' · '),
                        ),
                        onTap: () =>
                            context.push(AppRoutes.adminUserPath(user.id)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
