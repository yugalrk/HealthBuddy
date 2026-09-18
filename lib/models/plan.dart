/// The planned week: meals, days, and the whole-week roll-up.
library;

import 'food.dart';
import 'profile.dart';

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

  PlannedComponent withServings(double s) => PlannedComponent(recipe, s);

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

  /// Raw quantity of each ingredient the whole meal needs, in base units,
  /// summed across its dishes.
  Map<String, double> ingredientQuantities() {
    final out = <String, double>{};
    for (final c in components) {
      c.ingredientQuantities().forEach((id, q) {
        out[id] = (out[id] ?? 0) + q;
      });
    }
    return out;
  }

  String get title => components.map((c) => c.recipe.name).join(' + ');

  Set<String> get recipeIds => {for (final c in components) c.recipe.id};
}

class DayPlan {
  const DayPlan(this.dayIndex, this.meals, {int? weekday})
      : weekday = weekday ?? dayIndex % 7;

  /// Days since the plan started: 0 is the first day, and the day of the main
  /// shop.
  final int dayIndex;

  /// 0 = Monday. The week starts on whatever day it was planned.
  final int weekday;
  final List<PlannedMeal> meals;

  String get dayName => weekdayNames[weekday];
  bool get isWeekend => weekday >= 5;

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
    this.startWeekday = 0,
  });

  /// Weekday of day 0, where 0 = Monday.
  final int startWeekday;

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

  /// Ingredients the household asked to avoid that the plan still contains.
  ///
  /// Normally empty. It is non-empty only when avoiding something would have
  /// left a meal with nothing to cook — salt, for instance, appears in every
  /// savoury recipe. The app shows this rather than quietly serving food
  /// someone said they did not want.
  Set<String> avoidedButPresent(Set<String> avoid) {
    if (avoid.isEmpty) return const {};
    return ingredientTotals().keys.where(avoid.contains).toSet();
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

  /// Planned quantity of each ingredient, per day.
  List<Map<String, double>> ingredientsByDay() => [
        for (final d in days)
          () {
            final out = <String, double>{};
            for (final m in d.meals) {
              m.ingredientQuantities().forEach((id, q) {
                out[id] = (out[id] ?? 0) + q;
              });
            }
            return out;
          }()
      ];

  /// The plan is stored as recipe ids and portions rather than regenerated
  /// from its seed, because once the week has been adjusted to what the
  /// household actually ate, the seed alone no longer reproduces it.
  Map<String, dynamic> toJson() => {
        'seed': seed,
        'generatedAt': generatedAt.toIso8601String(),
        'startWeekday': startWeekday,
        'days': [
          for (final d in days)
            {
              'day': d.dayIndex,
              'weekday': d.weekday,
              'meals': [
                for (final m in d.meals)
                  {
                    'type': m.type.name,
                    'components': [
                      for (final c in m.components) [c.recipe.id, c.servings]
                    ],
                  }
              ],
            }
        ],
      };

  /// Null when a stored recipe no longer exists, so the caller can plan afresh
  /// rather than show a week with holes in it.
  static WeekPlan? fromJson(
      Map<String, dynamic> j, Map<String, Recipe> recipesById) {
    final days = <DayPlan>[];
    for (final dj in (j['days'] as List).cast<Map<String, dynamic>>()) {
      final meals = <PlannedMeal>[];
      for (final mj in (dj['meals'] as List).cast<Map<String, dynamic>>()) {
        final comps = <PlannedComponent>[];
        for (final c in (mj['components'] as List).cast<List>()) {
          final r = recipesById[c[0] as String];
          if (r == null) return null;
          comps.add(PlannedComponent(r, (c[1] as num).toDouble()));
        }
        meals.add(PlannedMeal(MealType.parse(mj['type'] as String), comps));
      }
      days.add(DayPlan(dj['day'] as int, meals, weekday: dj['weekday'] as int));
    }
    return WeekPlan(
      days: days,
      seed: j['seed'] as int,
      generatedAt: DateTime.parse(j['generatedAt'] as String),
      startWeekday: j['startWeekday'] as int? ?? 0,
    );
  }
}

/// What actually happened to a planned meal.
enum MealOutcome {
  asPlanned('As planned'),
  half('About half'),
  skipped('Skipped'),
  other('Something else');

  const MealOutcome(this.label);
  final String label;

  /// Share of the meal's ingredients taken out of the kitchen. Food not cooked
  /// is still in the fridge, and the rest of the week should use it.
  double get ingredientShare => switch (this) {
        MealOutcome.asPlanned => 1.0,
        MealOutcome.half => 0.5,
        MealOutcome.skipped || MealOutcome.other => 0.0,
      };

  /// What the household most likely took in, given what was planned.
  ///
  /// For [other] we know nothing about the food, so we assume it was about as
  /// filling as the planned meal but, like most food eaten out or grabbed in a
  /// hurry, carried about half the protein, fibre, iron and calcium. The app
  /// says so when this is chosen.
  Nutrients eaten(Nutrients planned) => switch (this) {
        MealOutcome.asPlanned => planned,
        MealOutcome.half => planned * 0.5,
        MealOutcome.skipped => Nutrients.zero,
        MealOutcome.other => Nutrients(
            kcal: planned.kcal,
            fat: planned.fat,
            carb: planned.carb,
            protein: planned.protein * 0.5,
            fibre: planned.fibre * 0.5,
            iron: planned.iron * 0.5,
            calcium: planned.calcium * 0.5,
          ),
      };
}

/// The household's end-of-day answer about how closely a day's plan was
/// followed. A meal with no answer is taken as eaten as planned.
class DayFeedback {
  const DayFeedback(this.dayIndex, this.meals);
  final int dayIndex;
  final Map<MealType, MealOutcome> meals;

  MealOutcome outcomeOf(MealType t) => meals[t] ?? MealOutcome.asPlanned;

  bool get followedFully =>
      meals.values.every((o) => o == MealOutcome.asPlanned);

  /// What was eaten on [day], given this feedback.
  Nutrients eaten(DayPlan day, Map<String, Ingredient> byId) => Nutrients.sum(
      day.meals.map((m) => outcomeOf(m.type).eaten(m.nutrients(byId))));

  /// What was taken out of the kitchen on [day].
  Map<String, double> used(DayPlan day) {
    final out = <String, double>{};
    for (final m in day.meals) {
      final share = outcomeOf(m.type).ingredientShare;
      if (share <= 0) continue;
      m.ingredientQuantities().forEach((id, q) {
        out[id] = (out[id] ?? 0) + q * share;
      });
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'day': dayIndex,
        'meals': {for (final e in meals.entries) e.key.name: e.value.name},
      };

  static DayFeedback fromJson(Map<String, dynamic> j) => DayFeedback(
        j['day'] as int,
        {
          for (final e in (j['meals'] as Map<String, dynamic>).entries)
            MealType.parse(e.key): MealOutcome.values.byName(e.value as String)
        },
      );
}
