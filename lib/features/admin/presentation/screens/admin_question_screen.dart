import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/result.dart';
import '../../../catalog/data/catalog_repository.dart';
import '../../../catalog/domain/catalog_models.dart';
import '../../data/admin_repository.dart';
import '../../domain/admin_models.dart';
import '../widgets/admin_choice.dart';

class AdminQuestionScreen extends ConsumerStatefulWidget {
  const AdminQuestionScreen({this.questionId, super.key});

  /// Null creates a question. Otherwise loads [questionId].
  final String? questionId;

  @override
  ConsumerState<AdminQuestionScreen> createState() =>
      _AdminQuestionScreenState();
}

class _AdminQuestionScreenState extends ConsumerState<AdminQuestionScreen> {
  final _stem = TextEditingController();
  final _marks = TextEditingController();
  final _chapter = TextEditingController();
  final _topic = TextEditingController();
  final _optionA = TextEditingController();
  final _optionB = TextEditingController();
  final _optionC = TextEditingController();
  final _optionD = TextEditingController();
  final _exp1 = TextEditingController();
  final _exp2 = TextEditingController();
  final _answer = TextEditingController();
  final _year = TextEditingController();
  final _paperName = TextEditingController();

  List<CatalogSubject> _subjects = const [];
  List<University> _universities = const [];
  List<College> _colleges = const [];
  List<AdminAppearance> _appearances = const [];
  String _publicCode = '';

  String? _subjectId;
  String _kind = 'pyq_theory';
  String _difficulty = 'should';
  String _plan = 'free';
  String _correct = 'A';
  var _active = true;
  String? _universityId;
  String? _collegeId;
  int _month = 5;
  String _examType = 'prof';

  var _loading = true;
  var _busy = false;
  String? _error;

  bool get _isNew => widget.questionId == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _stem.dispose();
    _marks.dispose();
    _chapter.dispose();
    _topic.dispose();
    _optionA.dispose();
    _optionB.dispose();
    _optionC.dispose();
    _optionD.dispose();
    _exp1.dispose();
    _exp2.dispose();
    _answer.dispose();
    _year.dispose();
    _paperName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final catalog = ref.read(catalogRepositoryProvider);
    final subjects = await catalog.fetchSubjects();
    final universities = await catalog.fetchUniversities();
    AdminQuestionDetail? detail;
    String? error;
    if (widget.questionId != null) {
      final loaded = await ref
          .read(adminRepositoryProvider)
          .getQuestion(widget.questionId!);
      switch (loaded) {
        case Success(:final value):
          detail = value;
        case Failure(:final message):
          error = message;
      }
    }
    if (!mounted) return;
    if (detail != null) _apply(detail);
    setState(() {
      _subjects = switch (subjects) {
        Success(:final value) => value,
        Failure() => const [],
      };
      _universities = switch (universities) {
        Success(:final value) => value,
        Failure() => const [],
      };
      _error = error;
      _loading = false;
    });
  }

  void _apply(AdminQuestionDetail detail) {
    _stem.text = detail.questionText;
    _marks.text = detail.marks?.toString() ?? '';
    _chapter.text = detail.chapterName ?? '';
    _topic.text = detail.topicName ?? '';
    _optionA.text = detail.optionA ?? '';
    _optionB.text = detail.optionB ?? '';
    _optionC.text = detail.optionC ?? '';
    _optionD.text = detail.optionD ?? '';
    _exp1.text = detail.explanationText ?? '';
    _exp2.text = detail.explanationDeep ?? '';
    _answer.text = detail.sampleAnswer ?? '';
    _subjectId = detail.subjectId;
    _kind = detail.kind;
    _difficulty = detail.difficulty;
    _plan = detail.requiredPlan;
    _correct = detail.correctOption ?? 'A';
    _active = detail.isActive;
    _appearances = detail.appearances;
    _publicCode = detail.publicCode;
  }

  Future<void> _reloadAppearances() async {
    final id = widget.questionId;
    if (id == null) return;
    final loaded = await ref.read(adminRepositoryProvider).getQuestion(id);
    if (!mounted) return;
    if (loaded case Success(:final value)) {
      setState(() => _appearances = value.appearances);
    }
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

  Future<void> _save() async {
    final subjectId = _subjectId;
    if (subjectId == null) {
      setState(() => _error = 'Choose a subject that already exists.');
      return;
    }
    num? marks;
    final marksText = _marks.text.trim();
    if (marksText.isNotEmpty) {
      marks = num.tryParse(marksText);
      if (marks == null) {
        setState(() => _error = 'Marks must be a number.');
        return;
      }
    }

    AdminSittingInput? sitting;
    if (_isNew) {
      final year = int.tryParse(_year.text.trim());
      if (_universityId == null || year == null) {
        setState(() => _error = 'A new question needs a university and year.');
        return;
      }
      sitting = AdminSittingInput(
        universityId: _universityId!,
        collegeId: _collegeId,
        examYear: year,
        examMonth: _month,
        paperName: _blank(_paperName.text),
        examType: _examType,
      );
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(adminRepositoryProvider)
        .saveQuestion(
          AdminQuestionInput(
            id: widget.questionId,
            subjectId: subjectId,
            questionText: _stem.text.trim(),
            kind: _kind,
            marks: marks,
            difficulty: _difficulty,
            requiredPlan: _plan,
            isActive: _active,
            optionA: _blank(_optionA.text),
            optionB: _blank(_optionB.text),
            optionC: _blank(_optionC.text),
            optionD: _blank(_optionD.text),
            correctOption: _kind == 'mcq' ? _correct : null,
            explanationText: _blank(_exp1.text),
            explanationDeep: _blank(_exp2.text),
            sampleAnswer: _blank(_answer.text),
            chapterName: _blank(_chapter.text),
            topicName: _blank(_topic.text),
            sitting: sitting,
          ),
        );
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        if (_isNew) {
          context.pushReplacement(AppRoutes.adminQuestionPath(value));
          return;
        }
        setState(() => _busy = false);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Question saved.')));
        }
      case Failure(:final message):
        setState(() {
          _busy = false;
          _error = message;
        });
    }
  }

  Future<void> _editAppearance(AdminAppearance? existing) async {
    final id = widget.questionId;
    if (id == null) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _SittingDialog(questionId: id, existing: existing),
    );
    if (saved == true) await _reloadAppearances();
  }

  Future<void> _deleteAppearance(AdminAppearance appearance) async {
    final id = widget.questionId;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this paper?'),
        content: const Text(
          'The question stays. The sheet row is removed on the next pull.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await ref
        .read(adminRepositoryProvider)
        .deleteAppearance(questionId: id, examPaperId: appearance.examPaperId);
    if (!mounted) return;
    if (result case Failure(:final message)) {
      setState(() => _error = message);
      return;
    }
    await _reloadAppearances();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isNew
              ? 'New question'
              : _publicCode.isEmpty
              ? 'Edit question'
              : 'Edit question · $_publicCode',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.md),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Text(
            'Free tier is plan Free. Pull app edits in the sheet before the next sync, or a blank required_plan cell resets this to free.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: Spacing.md),
          AdminChoice(
            label: 'Subject',
            value: _subjectId,
            items: [
              for (final subject in _subjects) (subject.id, subject.name),
            ],
            onChanged: (id) => setState(() => _subjectId = id),
          ),
          const SizedBox(height: Spacing.sm),
          AdminChoice(
            label: 'Type',
            value: _kind,
            items: const [('pyq_theory', 'Theory'), ('mcq', 'MCQ')],
            onChanged: (id) => setState(() => _kind = id ?? 'pyq_theory'),
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _stem,
            decoration: const InputDecoration(labelText: 'Question'),
            minLines: 3,
            maxLines: 8,
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _marks,
            decoration: const InputDecoration(labelText: 'Marks'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: Spacing.sm),
          AdminChoice(
            label: 'Difficulty',
            value: _difficulty,
            items: adminDifficulties,
            onChanged: (id) => setState(() => _difficulty = id ?? 'should'),
          ),
          const SizedBox(height: Spacing.sm),
          AdminChoice(
            label: 'Plan required',
            value: _plan,
            items: adminPlans,
            onChanged: (id) => setState(() => _plan = id ?? 'free'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Visible to students'),
            value: _active,
            onChanged: _busy
                ? null
                : (value) => setState(() => _active = value),
          ),
          TextField(
            controller: _chapter,
            decoration: const InputDecoration(labelText: 'Chapter'),
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _topic,
            decoration: const InputDecoration(labelText: 'Topic'),
          ),
          if (_kind == 'mcq') ...[
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _optionA,
              decoration: const InputDecoration(labelText: 'Option A'),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _optionB,
              decoration: const InputDecoration(labelText: 'Option B'),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _optionC,
              decoration: const InputDecoration(labelText: 'Option C'),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _optionD,
              decoration: const InputDecoration(labelText: 'Option D'),
            ),
            const SizedBox(height: Spacing.sm),
            AdminChoice(
              label: 'Correct option',
              value: _correct,
              items: const [('A', 'A'), ('B', 'B'), ('C', 'C'), ('D', 'D')],
              onChanged: (id) => setState(() => _correct = id ?? 'A'),
            ),
          ],
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _exp1,
            decoration: const InputDecoration(labelText: 'Short explanation'),
            minLines: 2,
            maxLines: 6,
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _exp2,
            decoration: const InputDecoration(labelText: 'Longer explanation'),
            minLines: 2,
            maxLines: 6,
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _answer,
            decoration: const InputDecoration(
              labelText: 'Model answer',
              helperText: 'Shown to Pro and above. Leave blank to remove it.',
            ),
            minLines: 2,
            maxLines: 8,
          ),
          if (_isNew) ...[
            const SizedBox(height: Spacing.lg),
            Text('First paper', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            AdminChoice(
              label: 'University',
              value: _universityId,
              items: [
                for (final university in _universities)
                  (university.id, '${university.code} · ${university.name}'),
              ],
              onChanged: _onUniversity,
            ),
            const SizedBox(height: Spacing.sm),
            AdminChoice(
              label: 'College',
              value: _collegeId,
              allowEmpty: true,
              items: [
                for (final college in _colleges) (college.id, college.label),
              ],
              onChanged: (id) => setState(() => _collegeId = id),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _year,
              decoration: const InputDecoration(labelText: 'Year'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: Spacing.sm),
            AdminChoice(
              label: 'Month',
              value: '$_month',
              items: [
                for (var month = 1; month <= 12; month++)
                  ('$month', adminMonthName(month)),
              ],
              onChanged: (id) =>
                  setState(() => _month = int.tryParse(id ?? '') ?? 5),
            ),
            const SizedBox(height: Spacing.sm),
            AdminChoice(
              label: 'Exam type',
              value: _examType,
              items: adminExamTypes,
              onChanged: (id) => setState(() => _examType = id ?? 'prof'),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _paperName,
              decoration: const InputDecoration(
                labelText: 'Paper',
                hintText: 'Paper I',
              ),
            ),
          ] else ...[
            const SizedBox(height: Spacing.lg),
            Row(
              children: [
                Text('Papers', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: _busy ? null : () => _editAppearance(null),
                  child: const Text('Add paper'),
                ),
              ],
            ),
            for (final appearance in _appearances)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(appearance.label),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Edit',
                      onPressed: () => _editAppearance(appearance),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () => _deleteAppearance(appearance),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: Spacing.lg),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save question'),
          ),
          const SizedBox(height: Spacing.xl),
        ],
      ),
    );
  }
}

class _SittingDialog extends ConsumerStatefulWidget {
  const _SittingDialog({required this.questionId, this.existing});

  final String questionId;
  final AdminAppearance? existing;

  @override
  ConsumerState<_SittingDialog> createState() => _SittingDialogState();
}

class _SittingDialogState extends ConsumerState<_SittingDialog> {
  final _year = TextEditingController();
  final _paper = TextEditingController();
  List<University> _universities = const [];
  List<College> _colleges = const [];
  String? _universityId;
  String? _collegeId;
  int _month = 5;
  String _examType = 'prof';
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _universityId = existing.universityId;
      _collegeId = existing.collegeId;
      _year.text = existing.examYear == 0 ? '' : '${existing.examYear}';
      _month = existing.examMonth ?? 5;
      _paper.text = existing.paperName ?? '';
      _examType = existing.examType;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _year.dispose();
    _paper.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final catalog = ref.read(catalogRepositoryProvider);
    final universities = await catalog.fetchUniversities();
    if (!mounted) return;
    setState(() {
      _universities = switch (universities) {
        Success(:final value) => value,
        Failure() => const [],
      };
    });
    final universityId = _universityId;
    if (universityId != null) {
      final colleges = await catalog.fetchColleges(universityId);
      if (!mounted) return;
      if (colleges case Success(:final value)) {
        setState(() => _colleges = value);
      }
    }
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
    if (result case Success(:final value)) setState(() => _colleges = value);
  }

  Future<void> _save() async {
    final year = int.tryParse(_year.text.trim());
    final universityId = _universityId;
    if (universityId == null || year == null) {
      setState(() => _error = 'Choose a university and a year.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(adminRepositoryProvider)
        .saveAppearance(
          AdminSittingInput(
            questionId: widget.questionId,
            examPaperId: widget.existing?.examPaperId,
            universityId: universityId,
            collegeId: _collegeId,
            examYear: year,
            examMonth: _month,
            paperName: _blank(_paper.text),
            examType: _examType,
          ),
        );
    if (!mounted) return;
    switch (result) {
      case Success():
        Navigator.pop(context, true);
      case Failure(:final message):
        setState(() {
          _busy = false;
          _error = message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add paper' : 'Edit paper'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            AdminChoice(
              label: 'University',
              value: _universityId,
              items: [
                for (final university in _universities)
                  (university.id, '${university.code} · ${university.name}'),
              ],
              onChanged: _onUniversity,
            ),
            const SizedBox(height: Spacing.sm),
            AdminChoice(
              label: 'College',
              value: _collegeId,
              allowEmpty: true,
              items: [
                for (final college in _colleges) (college.id, college.label),
              ],
              onChanged: (id) => setState(() => _collegeId = id),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _year,
              decoration: const InputDecoration(labelText: 'Year'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: Spacing.sm),
            AdminChoice(
              label: 'Month',
              value: '$_month',
              items: [
                for (var month = 1; month <= 12; month++)
                  ('$month', adminMonthName(month)),
              ],
              onChanged: (id) =>
                  setState(() => _month = int.tryParse(id ?? '') ?? 5),
            ),
            const SizedBox(height: Spacing.sm),
            AdminChoice(
              label: 'Exam type',
              value: _examType,
              items: adminExamTypes,
              onChanged: (id) => setState(() => _examType = id ?? 'prof'),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _paper,
              decoration: const InputDecoration(labelText: 'Paper'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

String? _blank(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
