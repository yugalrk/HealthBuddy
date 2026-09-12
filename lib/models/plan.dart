/// The planned week: meals, days, and the whole-week roll-up.
library;

import 'food.dart';

/// One recipe within a meal, at a chosen scale.
///
/// [servings] is a continuous multiple of a single recipe serving, so a staple
/// can be 2.5 rotis and a dal can be 3.2 portions for a household of three.
class PlannedComponent {
  const PlannedComponent(this.recipe, this.servings);
  final Recipe recipe;
  final double servings;

  Nutrients nutrients(Map<String, Ingredient> byId) =>
      recipe.perServing(byId) * servings;

  /// Quantity of each ingredient actually consumed, in base units.
  Map<String, double> ingredientQuantities() {
    final scale = servings / recipe.servings;
    return {
      for (final l in recipe.lines) l.ingredientId: l.qty * scale,
    };
  }

  /// "3 rotis", "2.5 katori rice", or "Dal Tadka ×3".
  String portionLabel() {
    final unit = recipe.portionUnit;
    final n = servings;
    final rounded = (n * 2).round() / 2;
    final numText =
        rounded == rounded.roundToDouble() ? rounded.toStringAsFixed(0) : rounded.toStringAsFixed(1);
    if (unit != null) {
      return '$numText $unit${rounded == 1 ? '' : 's'}';
    }
    return '×$numText';
  }
}

class PlannedMeal {
  const PlannedMeal(this.type, this.components);
  final MealType type;
  final List<PlannedComponent> components;

  Nutrients nutrients(Map<String, Ingredient> byId) =>
      Nutrients.sum(components.map((c) => c.nutrients(byId)));

  int get prepMin =>
      components.fold(0, (a, c) => a + c.recipe.prepMin);

  String get title => components.map((c) => c.recipe.name).join(' + ');

  Set<String> get recipeIds => {for (final c in components) c.recipe.id};
}

class DayPlan {
  const DayPlan(this.dayIndex, this.meals);

  /// 0 = Monday.
  final int dayIndex;
  final List<PlannedMeal> meals;

  static const dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];

  String get dayName => dayNames[dayIndex % 7];
  bool get isWeekend => dayIndex >= 5;

  Nutrients nutrients(Map<String, Ingredient> byId) =>
      Nutrients.sum(meals.map((m) => m.nutrients(byId)));

  PlannedMeal? mealOf(MealType t) {
    for (final m in meals) {
      if (m.type == t) return m;
    }
    return null;
  }
}

class WeekPlan {
  const WeekPlan({
    required this.days,
    required this.seed,
    required this.generatedAt,
  });

  final List<DayPlan> days;

  /// Seed that produced this plan. Regenerating advances it, so plans are
  /// reproducible and testable.
  final int seed;
  final DateTime generatedAt;

  Nutrients nutrients(Map<String, Ingredient> byId) =>
      Nutrients.sum(days.map((d) => d.nutrients(byId)));

  /// Total consumed quantity per ingredient across the week, in base units.
  Map<String, double> ingredientTotals() {
    final out = <String, double>{};
    for (final d in days) {
      for (final m in d.meals) {
        for (final c in m.components) {
          c.ingredientQuantities().forEach((id, q) {
            out[id] = (out[id] ?? 0) + q;
          });
        }
      }
    }
    return out;
  }

  /// How often each recipe appears — drives the variety display.
  Map<String, int> recipeFrequency() {
    final out = <String, int>{};
    for (final d in days) {
      for (final m in d.meals) {
        for (final c in m.components) {
          out[c.recipe.id] = (out[c.recipe.id] ?? 0) + 1;
        }
      }
    }
    return out;
  }
}
