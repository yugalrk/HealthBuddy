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
