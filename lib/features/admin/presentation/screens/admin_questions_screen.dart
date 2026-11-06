import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/result.dart';
import '../../data/admin_repository.dart';
import '../../domain/admin_models.dart';

class AdminQuestionsScreen extends ConsumerStatefulWidget {
  const AdminQuestionsScreen({super.key});

  @override
  ConsumerState<AdminQuestionsScreen> createState() =>
      _AdminQuestionsScreenState();
}

class _AdminQuestionsScreenState extends ConsumerState<AdminQuestionsScreen> {
  final _query = TextEditingController();
  var _loading = false;
  String? _error;
  List<AdminQuestionSummary> _questions = const [];

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
        .searchQuestions(_query.text);
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        setState(() {
          _questions = value;
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
      appBar: AppBar(title: const Text('Questions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.adminQuestionNew),
        icon: const Icon(Icons.add),
        label: const Text('New question'),
      ),
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
                      labelText: 'Stem or subject',
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
                    itemCount: _questions.length,
                    itemBuilder: (context, index) {
                      final question = _questions[index];
                      final subject = question.subjectName ?? 'No subject';
                      return ListTile(
                        title: Text(
                          question.questionText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '$subject · ${question.kind} · ${question.requiredPlan}'
                          '${question.isActive ? '' : ' · hidden'}'
                          ' · ${question.appearanceCount} paper'
                          '${question.appearanceCount == 1 ? '' : 's'}',
                        ),
                        onTap: () async {
                          await context.push(
                            AppRoutes.adminQuestionPath(question.id),
                          );
                          if (mounted) await _search();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
