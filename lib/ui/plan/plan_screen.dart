/// The week's meals.
library;

import 'package:flutter/material.dart';

import '../../engine/adapt.dart';
import '../../models/food.dart';
import '../../models/plan.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final plan = app.plan;
    final progress = app.progress;

    if (plan == null || progress == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final dayTarget = app.dailyTargets;
    final pending = app.pendingFeedbackDay;
    final adaptation = app.lastAdaptation;

    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: const Text('This week'),
          actions: [
            IconButton(
              tooltip: 'Plan a new week from today',
              onPressed: app.generating ? null : () => _newWeek(context),
              icon: app.generating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          sliver: SliverList.list(children: [
            if (app.weekOver)
              _WeekOverCard(app: app)
            else if (pending != null)
              _FeedbackPrompt(app: app, day: pending),
            if (adaptation != null && !app.weekOver)
              _AdaptationNote(app: app, adaptation: adaptation),
          ]),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList.builder(
            itemCount: plan.days.length,
            itemBuilder: (context, i) => _DayCard(
              app: app,
              day: plan.days[i],
              dayTarget: dayTarget,
              feedback: progress.feedback[plan.days[i].dayIndex],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _newWeek(BuildContext context) async {
    final underway = app.progress!.feedback.isNotEmpty && !app.weekOver;
    if (underway) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Start a new week?'),
          content: const Text(
              'This plans seven fresh days from today with a new shopping '
              'list. What you told us about this week so far will be cleared.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Start again')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await app.generateNewWeek();
  }
}

/// How to refer to a day in a question: "today", "yesterday", or its name.
String _dayWord(AppState app, DayPlan day) {
  final ago = app.todayIndex - day.dayIndex;
  if (ago == 0) return 'today';
  if (ago == 1) return 'yesterday';
  return day.dayName;
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.app,
    required this.day,
    required this.dayTarget,
    required this.feedback,
  });
  final AppState app;
  final DayPlan day;
  final Nutrients dayTarget;
  final DayFeedback? feedback;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ings = app.food.ingredients;
    final n = feedback?.eaten(day, ings) ?? day.nutrients(ings);
    final ratio = dayTarget.kcal <= 0 ? 1.0 : n.kcal / dayTarget.kcal;
    final isToday = day.dayIndex == app.todayIndex;
    final past = day.dayIndex < app.todayIndex;
    final rules = app.profile.rulesOn(day.weekday).toList();
    final names = {for (final m in app.profile.members) m.id: m.name};

    Widget badge(String text, Color bg, Color fg) => Container(
          margin: const EdgeInsets.only(left: 8),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(text, style: TextStyle(fontSize: 11, color: fg)),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        shape: isToday
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: scheme.primary, width: 1.5),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    day.dayName,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: past && !isToday ? scheme.onSurfaceVariant : null),
                  ),
                  const SizedBox(width: 6),
                  Text(formatShortDate(app.dateOf(day.dayIndex)),
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant)),
                  if (isToday)
                    badge('today', scheme.primary, scheme.onPrimary)
                  else if (day.isWeekend)
                    badge('weekend', scheme.secondaryContainer,
                        scheme.onSecondaryContainer),
                  Expanded(
                    child: Text(
                      '${n.kcal.round()} kcal · ${n.protein.round()}g P',
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0).toDouble(),
                minHeight: 3,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
              for (final r in rules)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.event_repeat,
                          size: 16, color: scheme.tertiary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${describeAvoided(r, ings, app.profile.diet)} today, '
                          'for ${r.memberIds.map((id) => names[id] ?? 'someone').join(', ')}',
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.3,
                              color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              if (feedback != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      Icon(
                          feedback!.followedFully
                              ? Icons.check_circle
                              : Icons.edit_note,
                          size: 16,
                          color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          feedback!.followedFully
                              ? 'Went to plan'
                              : 'Changed from the plan — the figures show what '
                                  'was actually eaten',
                          style: TextStyle(
                              fontSize: 12.5, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              for (final meal in day.meals)
                _MealRow(
                  meal: meal,
                  app: app,
                  outcome: feedback?.meals[meal.type],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackPrompt extends StatelessWidget {
  const _FeedbackPrompt({required this.app, required this.day});
  final AppState app;
  final int day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = app.plan!.days[day];
    final word = _dayWord(app, d);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: scheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.rate_review_outlined,
                      color: scheme.onPrimaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'How did $word go?',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Tell us what was actually eaten. If anything was skipped or '
                'swapped, we adjust the rest of the week to make it up and to '
                'use the food still in your kitchen.',
                style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: app.generating
                          ? null
                          : () => _submit(context, DayFeedback(day, {
                                for (final m in d.meals)
                                  m.type: MealOutcome.asPlanned
                              })),
                      child: const Text('All as planned'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: app.generating
                          ? null
                          : () async {
                              final fb = await showModalBottomSheet<DayFeedback>(
                                context: context,
                                isScrollControlled: true,
                                builder: (_) =>
                                    _FeedbackSheet(app: app, day: d),
                              );
                              if (fb != null && context.mounted) {
                                await _submit(context, fb);
                              }
                            },
                      child: const Text('Something changed'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context, DayFeedback fb) async {
    final messenger = ScaffoldMessenger.of(context);
    final before = app.lastAdaptation;
    await app.recordFeedback(fb);
    final after = app.lastAdaptation;
    messenger.showSnackBar(SnackBar(
      content: Text(after != null && !identical(after, before)
          ? 'Adjusted the rest of the week'
          : 'Thanks — the plan stays as it is'),
    ));
  }
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet({required this.app, required this.day});
  final AppState app;
  final DayPlan day;

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  late final Map<MealType, MealOutcome> _outcomes = {
    for (final m in widget.day.meals) m.type: MealOutcome.asPlanned
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ings = widget.app.food.ingredients;
    final word = _dayWord(widget.app, widget.day);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Text(
            'What was eaten ${word == widget.day.dayName ? 'on $word' : word}?',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'For the household as a whole. Rough is fine.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          for (final meal in widget.day.meals) ...[
            const SizedBox(height: 18),
            Text(meal.type.label,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              _MealAmounts(meal, ings)
                  .main
                  .take(3)
                  .map((e) => e.ingredient.name)
                  .join(', '),
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final o in MealOutcome.values)
                  ChoiceChip(
                    label: Text(o.label),
                    selected: _outcomes[meal.type] == o,
                    onSelected: (_) => setState(() => _outcomes[meal.type] = o),
                  ),
              ],
            ),
          ],
          if (_outcomes.values.contains(MealOutcome.other)) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'For "Something else" we assume it was about as filling as '
                'the planned meal, with around half the protein, iron and '
                'calcium — typical of food eaten out or picked up on the way.',
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: scheme.onSurfaceVariant),
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context)
                .pop(DayFeedback(widget.day.dayIndex, {..._outcomes})),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _AdaptationNote extends StatelessWidget {
  const _AdaptationNote({required this.app, required this.adaptation});
  final AppState app;
  final WeekAdjustment adaptation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final adj = adaptation.dayAdjust;
    final plan = app.plan!;
    final from = adaptation.fromDay < plan.days.length
        ? plan.days[adaptation.fromDay].dayName
        : null;

    String signed(double v, String unit) =>
        '${v >= 0 ? '+' : '−'}${v.abs().round()} $unit';

    final lines = <String>[
      if (adj.protein.abs() >= 1 || adj.kcal.abs() >= 20)
        '${signed(adj.protein, 'g')} protein and ${signed(adj.kcal, 'kcal')} '
            'a day for the household from ${from ?? 'tomorrow'}, to '
            '${adj.protein >= 0 ? 'make up what was missed' : 'balance what was eaten'}.',
      'Food bought for meals that were not cooked is used first, while it '
          'is still fresh.',
      if (adj.protein.abs() >= (app.dailyTargets.protein * 0.19))
        'Part of the gap is too big to make up comfortably in the days left, '
            'so we have not tried to force it.',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(Icons.auto_fix_high, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Rest of the week adjusted',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                    for (final l in lines)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(l,
                            style: TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                color: scheme.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                icon: const Icon(Icons.close, size: 18),
                onPressed: app.dismissAdaptation,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekOverCard extends StatelessWidget {
  const _WeekOverCard({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: scheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This week is done',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer)),
              const SizedBox(height: 6),
              Text(
                'Plan the next seven days, with a fresh shopping list.',
                style: TextStyle(
                    fontSize: 13, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: app.generating ? null : app.generateNewWeek,
                child: const Text('Plan next week'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MealRow extends StatelessWidget {
  const _MealRow({required this.meal, required this.app, this.outcome});
  final PlannedMeal meal;
  final AppState app;

  /// How it went, once the household has said.
  final MealOutcome? outcome;

  IconData get _icon => switch (meal.type) {
        MealType.breakfast => Icons.wb_twilight,
        MealType.lunch => Icons.light_mode_outlined,
        MealType.snack => Icons.cookie_outlined,
        MealType.dinner => Icons.nightlight_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = meal.nutrients(app.food.ingredients);
    final amounts = _MealAmounts(meal, app.food.ingredients);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showMealDetail(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon, size: 18, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        meal.type.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (outcome != null &&
                          outcome != MealOutcome.asPlanned) ...[
                        const SizedBox(width: 8),
                        Text(
                          outcome!.label.toLowerCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: scheme.tertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  for (final e in amounts.main)
                    _AmountLine(
                      name: e.ingredient.name,
                      qty: formatCookQty(e.qty, e.ingredient.unit),
                    ),
                  if (amounts.flavour.isNotEmpty)
                    Text(
                      '+ ${amounts.flavour.length} spices & seasonings',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  const SizedBox(height: 4),
                  MacroRow(n: n, dense: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMealDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MealDetailSheet(meal: meal, app: app),
    );
  }
}

/// A meal's ingredients as amounts to cook, largest first.
///
/// Spices and seasonings are split out: at a few grams they carry no
/// nutritional weight, and listing "2 g hing" beside "250 g atta" buries the
/// amounts that actually decide whether the goal is met.
class _MealAmounts {
  _MealAmounts(PlannedMeal meal, Map<String, Ingredient> byId) {
    final entries = [
      for (final e in meal.ingredientQuantities().entries)
        if (byId[e.key] != null) (ingredient: byId[e.key]!, qty: e.value),
    ]..sort((a, b) => b.qty.compareTo(a.qty));
    for (final e in entries) {
      (e.ingredient.role == NutrientRole.flavour ? flavour : main).add(e);
    }
  }

  final List<({Ingredient ingredient, double qty})> main = [];
  final List<({Ingredient ingredient, double qty})> flavour = [];
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({required this.name, required this.qty, this.size = 14.5});
  final String name;
  final String qty;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 64,
            child: Text(qty,
                style: TextStyle(
                    fontSize: size, fontWeight: FontWeight.w700, height: 1.35)),
          ),
          Expanded(
            child: Text(name, style: TextStyle(fontSize: size, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class _MealDetailSheet extends StatelessWidget {
  const _MealDetailSheet({required this.meal, required this.app});
  final PlannedMeal meal;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ings = app.food.ingredients;
    final amounts = _MealAmounts(meal, ings);
    final people = app.profile.householdSize;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(meal.type.label,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'What to cook for ${people == 1 ? 'you' : 'all $people of you'} '
            'to stay on track. Uncooked weights — cook it however you like.',
            style: TextStyle(
                color: scheme.onSurfaceVariant, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 16),
          MacroRow(n: meal.nutrients(ings)),
          const SectionHeader('Amounts'),
          for (final e in amounts.main)
            _AmountLine(
              name: e.ingredient.name,
              qty: formatCookQty(e.qty, e.ingredient.unit),
              size: 14,
            ),
          if (amounts.flavour.isNotEmpty) ...[
            const SectionHeader('Spices & seasonings'),
            Text(
              amounts.flavour.map((e) => e.ingredient.name).join(', '),
              style: TextStyle(
                  fontSize: 13, height: 1.4, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// "250 g", "35 g", "1.2 kg" — rounded to what a kitchen scale or katori can
/// sensibly measure rather than the solver's exact output.
String formatCookQty(double qty, String unit) {
  if (qty >= 1000) {
    final v = qty / 1000;
    return '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${unit == 'ml' ? 'L' : 'kg'}';
  }
  final step = qty < 20 ? 1 : (qty < 100 ? 5 : 10);
  final rounded = (qty / step).round() * step;
  return '${rounded < 1 ? '<1' : rounded} $unit';
}
