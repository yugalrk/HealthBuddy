/// The week's meals.
library;

import 'package:flutter/material.dart';

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
    final scheme = Theme.of(context).colorScheme;

    if (plan == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final dayTarget = app.dailyTargets;

    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: const Text('This week'),
          actions: [
            IconButton(
              tooltip: 'Generate a different week',
              onPressed: app.generating ? null : () => app.generateNewWeek(),
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList.builder(
            itemCount: plan.days.length,
            itemBuilder: (context, i) {
              final day = plan.days[i];
              final n = day.nutrients(app.food.ingredients);
              final ratio = dayTarget.kcal <= 0 ? 1.0 : n.kcal / dayTarget.kcal;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              day.dayName,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w700),
                            ),
                            if (day.isWeekend) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: scheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('weekend',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: scheme.onSecondaryContainer)),
                              ),
                            ],
                            const Spacer(),
                            Text(
                              '${n.kcal.round()} kcal · ${n.protein.round()}g P',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant,
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
                        const SizedBox(height: 12),
                        for (final meal in day.meals)
                          _MealRow(meal: meal, app: app),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MealRow extends StatelessWidget {
  const _MealRow({required this.meal, required this.app});
  final PlannedMeal meal;
  final AppState app;

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
                  Text(
                    meal.type.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  for (final c in meal.components)
                    Text(
                      '${c.recipe.name}  ${c.portionLabel()}',
                      style: const TextStyle(fontSize: 14.5, height: 1.35),
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

class _MealDetailSheet extends StatelessWidget {
  const _MealDetailSheet({required this.meal, required this.app});
  final PlannedMeal meal;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ings = app.food.ingredients;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(meal.type.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: scheme.onSurfaceVariant,
              )),
          const SizedBox(height: 4),
          Text(meal.title,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('About ${meal.prepMin} minutes to cook',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          const SizedBox(height: 16),
          MacroRow(n: meal.nutrients(ings)),
          for (final c in meal.components) ...[
            SectionHeader('${c.recipe.name} — ${c.portionLabel()}'),
            Text(
              'Cooked quantities for your household',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            ...(() {
              final q = c.ingredientQuantities();
              final entries = q.entries.toList()
                ..sort((a, b) {
                  final an = ings[a.key]?.name ?? a.key;
                  final bn = ings[b.key]?.name ?? b.key;
                  return an.compareTo(bn);
                });
              return [
                for (final e in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(ings[e.key]?.name ?? e.key,
                              style: const TextStyle(fontSize: 14)),
                        ),
                        Text(
                          _fmt(e.value, ings[e.key]?.unit ?? 'g'),
                          style: TextStyle(
                              fontSize: 14, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
              ];
            })(),
          ],
        ],
      ),
    );
  }

  static String _fmt(double qty, String unit) {
    if (qty >= 1000) {
      final v = qty / 1000;
      return '${v.toStringAsFixed(v < 10 ? 2 : 1)} ${unit == 'ml' ? 'L' : 'kg'}';
    }
    return '${qty.round()} $unit';
  }
}
