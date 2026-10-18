import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/brand_assets.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/utils/soft_keyboard.dart';
import '../../../../core/utils/user_facing_error.dart';
import '../../../../core/widgets/async_status_views.dart';
import '../../../../core/widgets/comic_card.dart';
import '../../../../core/widgets/comic_mascot.dart';
import '../../../../core/widgets/comic_select_sheet.dart';
import '../../../../core/widgets/theme_mode_selector.dart';
import '../../../catalog/domain/catalog_models.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../catalog/presentation/widgets/year_picker.dart';
import '../../../profile/data/profile_repository.dart';
import '../../../profile/presentation/providers/user_profile_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _nameController = TextEditingController();
  var _step = 0;
  String? _state;
  String? _universityId;
  String? _collegeId;
  String? _phaseId;
  int _batchYear = DateTime.now().year;
  bool _saving = false;
  String? _error;

  static const _stepCount = 5;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty ||
        _universityId == null ||
        _collegeId == null ||
        _phaseId == null) {
      setState(() => _error = 'Fill in every field to continue.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final result = await ref
        .read(profileRepositoryProvider)
        .saveOnboarding(
          fullName: name,
          universityId: _universityId!,
          collegeId: _collegeId!,
          batchYear: _batchYear,
          mbbsPhaseId: _phaseId!,
        );

    if (!mounted) return;
    setState(() => _saving = false);

    switch (result) {
      case Success():
        await ref.read(userProfileProvider.notifier).refresh();
        if (!mounted) return;
        context.go(AppRoutes.home);
      case Failure(:final message):
        setState(() => _error = message);
    }
  }

  void _next() {
    if (_step == 1 && _nameController.text.trim().isEmpty) {
      setState(() => _error = 'Add your name.');
      return;
    }
    if (_step == 2 && _phaseId == null) {
      setState(() => _error = 'Pick your MBBS year.');
      return;
    }
    if (_step == 3 && _state == null) {
      setState(() => _error = 'Pick your state.');
      return;
    }
    setState(() {
      _error = null;
      _step += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final universities = ref.watch(universitiesProvider);
    final phases = ref.watch(mbbsPhasesProvider);
    final colleges = _universityId == null
        ? const AsyncValue<List<College>>.data([])
        : ref.watch(collegesProvider(_universityId!));

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            const Center(
              child: ComicMascot(
                asset: BrandAssets.mascotStudy,
                size: 120,
                heroTag: 'onboarding-docci',
              ),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'Tell ${BrandAssets.mascotName} where you study',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Step ${_step + 1} of $_stepCount',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              // TweenAnimationBuilder animates from whatever it last showed to
              // the new `end`, so the bar slides forward as steps advance.
              // `begin` only applies to the very first build.
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: (_step + 1) / _stepCount),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut,
                builder: (context, value, _) =>
                    LinearProgressIndicator(value: value, minHeight: 6),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            if (_step == 0) const ComicCard(child: ThemeModeSelector()),
            if (_step == 1)
              TextField(
                controller: _nameController,
                keyboardType: TextInputType.name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                stylusHandwritingEnabled: false,
                onTap: requestSoftKeyboard,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
            if (_step == 2) ...[
              Text(
                'Current MBBS year',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: Spacing.sm),
              phases.when(
                data: (items) {
                  return YearPickerRow(
                    phases: items,
                    selectedId: _phaseId,
                    onSelect: (id) => setState(() => _phaseId = id),
                    padding: EdgeInsets.zero,
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (e, _) =>
                    InlineErrorMessage(message: UserFacingError.display(e)),
              ),
            ],
            if (_step == 3) ...[
              Text(
                'Which state is your college in?',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: Spacing.sm),
              universities.when(
                data: (items) {
                  final states = statesWithUniversities(items);
                  return ComicSelectField<String>(
                    label: 'State',
                    items: states,
                    value: _state,
                    labelOf: (s) => s,
                    onSelected: (s) => setState(() {
                      if (_state != s) {
                        _universityId = null;
                        _collegeId = null;
                      }
                      _state = s;
                    }),
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (e, _) =>
                    InlineErrorMessage(message: UserFacingError.display(e)),
              ),
            ],
            if (_step == 4) ...[
              universities.when(
                data: (items) {
                  final inState = universitiesInState(items, _state);
                  final selected = inState.where((u) => u.id == _universityId);
                  return ComicSelectField<University>(
                    label: 'University',
                    items: inState,
                    value: selected.isEmpty ? null : selected.first,
                    labelOf: (u) => '${u.code} · ${u.name}',
                    placeholder: _state == null
                        ? 'Pick a state first'
                        : 'Tap to choose',
                    enabled: _state != null,
                    onSelected: (u) => setState(() {
                      _universityId = u.id;
                      _collegeId = null;
                    }),
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (e, _) =>
                    InlineErrorMessage(message: UserFacingError.display(e)),
              ),
              const SizedBox(height: Spacing.md),
              colleges.when(
                data: (items) {
                  final selected = items.where((c) => c.id == _collegeId);
                  return ComicSelectField<College>(
                    label: 'College',
                    items: items,
                    value: selected.isEmpty ? null : selected.first,
                    labelOf: (c) => c.label,
                    onSelected: (c) => setState(() => _collegeId = c.id),
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (e, _) =>
                    InlineErrorMessage(message: UserFacingError.display(e)),
              ),
              const SizedBox(height: Spacing.md),
              ComicSelectField<int>(
                label: 'Batch year',
                items: [
                  for (
                    var y = DateTime.now().year;
                    y >= DateTime.now().year - 6;
                    y--
                  )
                    y,
                ],
                value: _batchYear,
                labelOf: (y) => '$y',
                onSelected: (y) => setState(() => _batchYear = y),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Spacing.md),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            Row(
              children: [
                if (_step > 0)
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _error = null;
                      _step -= 1;
                    }),
                    child: const Text('Back'),
                  ),
                if (_step > 0) const SizedBox(width: Spacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving
                        ? null
                        : (_step == _stepCount - 1 ? _submit : _next),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _step == _stepCount - 1 ? 'Start studying' : 'Next',
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
