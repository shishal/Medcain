import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/result.dart';
import '../../data/admin_repository.dart';
import '../../domain/admin_models.dart';

class AdminAnnouncementsScreen extends ConsumerStatefulWidget {
  const AdminAnnouncementsScreen({super.key});

  @override
  ConsumerState<AdminAnnouncementsScreen> createState() =>
      _AdminAnnouncementsScreenState();
}

class _AdminAnnouncementsScreenState
    extends ConsumerState<AdminAnnouncementsScreen> {
  var _loading = true;
  String? _error;
  List<AdminAnnouncement> _items = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ref.read(adminRepositoryProvider).listAnnouncements();
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        setState(() {
          _items = value;
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
      appBar: AppBar(title: const Text('Notifications')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push(AppRoutes.adminAnnouncementNew);
          if (mounted) await _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return ListTile(
                  title: Text(item.title),
                  subtitle: Text(item.isActive ? 'Published' : 'Draft'),
                  onTap: () async {
                    await context.push(
                      AppRoutes.adminAnnouncementPath(item.id),
                    );
                    if (mounted) await _load();
                  },
                );
              },
            ),
    );
  }
}
