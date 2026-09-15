/// The weekly meal planner.
///
/// The optimisation unit is the **week**, not the meal. A meal that falls short
/// on protein pushes that deficit forward as a carry, so a light lunch is repaid
/// at dinner and a protein-short Tuesday is repaid by Wednesday. That is the
/// behaviour the app exists to provide.
///
/// Lunch and dinner are built as a thali: a protein `main` (dal, paneer, egg,
/// meat), a `staple` whose portion is solved to close the energy gap, and
/// optionally a vegetable `sabzi` and a `side`. Keeping the protein main
/// structurally mandatory is what stops the planner from centring a meal on a
/// near-zero-protein gourd dish.
///
/// The planner is deterministic given a seed, which makes it unit-testable and
/// makes "regenerate" reproducible.
library;

import 'dart:math' as math;

import '../models/food.dart';
import '../models/plan.dart';
import '../models/profile.dart';
import 'targets.dart';

/// Relative weights used when scoring how well a meal fits its target.
///
/// Protein is weighted highest because balancing it is the app's whole purpose;
/// energy next. Iron and calcium carry real weight too: they are the two
/// micronutrients most often short in Indian diets, and a planner that ignored
/// them would quietly produce iron-deficient weeks.
class ScoreWeights {
  const ScoreWeights({
    this.protein = 2.2,
    this.kcal = 1.0,
    this.fat = 0.4,
    this.carb = 0.4,
    this.fibre = 0.5,
    this.iron = 0.8,
    this.calcium = 0.8,
    this.repetition = 1.0,
    this.newIngredient = 0.35,
    this.liked = 0.4,
    this.disliked = 2.5,
    this.weekdayPrep = 0.25,
    this.jitter = 0.12,
  });

  final double protein;
  final double kcal;
  final double fat;
  final double carb;
  final double fibre;
  final double iron;
  final double calcium;
  final double repetition;
  final double newIngredient;
  final double liked;
  final double disliked;
  final double weekdayPrep;
  final double jitter;

  ScoreWeights copyWith({double? protein, double? iron, double? calcium}) =>
      ScoreWeights(
        protein: protein ?? this.protein,
        kcal: kcal,
        fat: fat,
        carb: carb,
        fibre: fibre,
        iron: iron ?? this.iron,
        calcium: calcium ?? this.calcium,
        repetition: repetition,
        newIngredient: newIngredient,
        liked: liked,
        disliked: disliked,
        weekdayPrep: weekdayPrep,
        jitter: jitter,
      );
}

/// Share of the day's energy allocated to each meal.
Map<MealType, double> mealEnergyShares({required bool includeSnacks}) =>
    includeSnacks
        ? const {
            MealType.breakfast: 0.25,
            MealType.lunch: 0.33,
            MealType.snack: 0.12,
            MealType.dinner: 0.30,
          }
        : const {
            MealType.breakfast: 0.28,
            MealType.lunch: 0.38,
            MealType.dinner: 0.34,
          };

/// Portion multipliers tried for the main dish, relative to the household's
/// standard portion count. Letting the main vary (not just the staple) is what
/// makes high protein targets reachable on a reduced energy budget: you cannot
/// get there by adding rotis.
const _mainPortionScales = [0.8, 1.0, 1.25, 1.5, 1.8];

/// Multipliers applied to the energy-closing staple portion.
///
/// Solving the staple purely to close the calorie gap dilutes protein: a dense
/// dal paired with a mountain of rice lands on the energy target and misses the
/// protein one. Offering smaller staple portions lets the optimiser trade rotis
/// for dal, which is what a person actually does when eating for protein.
const _stapleScales = [1.0, 0.8, 0.6];

/// Order meals are planned in, so the carry flows forward through the day.
const _mealOrder = [
  MealType.breakfast,
  MealType.lunch,
  MealType.snack,
  MealType.dinner,
];

double _snap(double v, int granularity) {
  final s = (v * granularity).round() / granularity;
  return s < 0 ? 0 : s;
}

/// Per-recipe values that never change during a run, hoisted out of the inner
/// scoring loop.
class _RecipeStatic {
  _RecipeStatic({
    required this.perServing,
    required this.ids,
    required this.likedFrac,
    required this.dislikedFrac,
  });
  final Nutrients perServing;
  final List<String> ids;
  final double likedFrac;
  final double dislikedFrac;
}

class MealPlanner {
  MealPlanner({
    required this.profile,
    required List<Recipe> recipes,
    required this.ingredients,
    this.weights = const ScoreWeights(),
  })  : recipes = recipes
            .where((r) => _isEdible(r, profile, ingredients, avoidDisliked: true))
            .toList(),
        _lenient = recipes
            .where((r) => _isEdible(r, profile, ingredients, avoidDisliked: false))
            .toList() {
    for (final r in _lenient) {
      final ids = r.ingredientIds.toList();
      var liked = 0;
      var disliked = 0;
      for (final id in ids) {
        if (profile.liked.contains(id)) liked++;
        if (profile.disliked.contains(id)) disliked++;
      }
      _static[r.id] = _RecipeStatic(
        perServing: r.perServing(ingredients),
        ids: ids,
        likedFrac: ids.isEmpty ? 0 : liked / ids.length,
        dislikedFrac: ids.isEmpty ? 0 : disliked / ids.length,
      );
    }
  }

  final Profile profile;

  /// Recipes that satisfy every restriction, including things to avoid.
  final List<Recipe> recipes;

  /// Same, but allowing avoided ingredients. Used only where honouring an
  /// avoidance would leave a meal slot with nothing to cook.
  final List<Recipe> _lenient;

  final Map<String, Ingredient> ingredients;
  final ScoreWeights weights;

  final Map<String, _RecipeStatic> _static = {};
  final Map<(MealType, RecipeRole), List<Recipe>> _candidateCache = {};

  /// Slot/role combinations where avoidances had to be relaxed to produce a
  /// meal at all. Surfaced to the user rather than silently ignored.
  final Set<RecipeRole> relaxedRoles = {};

  /// Hard filter.
  ///
  /// Diet type and allergens are always absolute. Avoided ingredients are too
  /// when [avoidDisliked] is set: if someone says they do not want brinjal,
  /// a plan containing brinjal is simply wrong, however well it scores.
  static bool _isEdible(
    Recipe r,
    Profile p,
    Map<String, Ingredient> ingredients, {
    required bool avoidDisliked,
  }) {
    if (!p.diet.admits(r.diet)) return false;
    for (final id in r.ingredientIds) {
      if (p.allergens.contains(id)) return false;
      if (avoidDisliked && p.disliked.contains(id)) return false;
    }
    return true;
  }

  /// Candidates for a slot, preferring recipes that honour every avoidance.
  ///
  /// Falls back to allowing avoided ingredients only when being strict would
  /// leave nothing to cook — a household that avoids onion should still get
  /// dinner. The fallback is recorded in [relaxedRoles] so the app can say so.
  List<Recipe> _candidates(MealType slot, RecipeRole role) =>
      _candidateCache[(slot, role)] ??= () {
        final strict = recipes
            .where((r) => r.role == role && r.slots.contains(slot))
            .toList(growable: false);
        if (strict.isNotEmpty || role == RecipeRole.sabzi ||
            role == RecipeRole.side) {
          // Sabzis and sides are optional, so an empty strict list is fine.
          return strict;
        }
        final lenient = _lenient
            .where((r) => r.role == role && r.slots.contains(slot))
            .toList(growable: false);
        if (lenient.isNotEmpty) relaxedRoles.add(role);
        return lenient;
      }();

  Nutrients _perServing(Recipe r) => _static[r.id]!.perServing;

  WeekPlan generate({int seed = 0}) {
    final rng = math.Random(seed);
    final dayTarget = householdDailyTargets(profile);
    final portions = householdPortions(profile);
    final shares = mealEnergyShares(includeSnacks: profile.includeSnacks);

    // Ingredients already committed to this week - reusing them keeps the
    // shopping list short, so they score cheaper than introducing new ones.
    final weekIngredients = <String>{...profile.pantry};
    final lastUsedDay = <String, int>{};
    final useCount = <String, int>{};

    final days = <DayPlan>[];
    var carry = Nutrients.zero;

    for (var d = 0; d < 7; d++) {
      final meals = <PlannedMeal>[];
      final isWeekend = d >= 5;

      for (final slot in _mealOrder) {
        final share = shares[slot];
        if (share == null) continue;

        // Apply part of the accumulated carry to this slot, so corrections are
        // spread across meals rather than dumped on the next one.
        final slotTarget = dayTarget * share + carry * (0.5 * share / 0.30);

        final meal = slot == MealType.breakfast || slot == MealType.snack
            ? _planSingleDish(
                slot: slot,
                slotTarget: slotTarget,
                portions: portions,
                dayIndex: d,
                isWeekend: isWeekend,
                weekIngredients: weekIngredients,
                lastUsedDay: lastUsedDay,
                useCount: useCount,
                rng: rng,
              )
            : _planThali(
                slot: slot,
                slotTarget: slotTarget,
                portions: portions,
                dayIndex: d,
                isWeekend: isWeekend,
                weekIngredients: weekIngredients,
                lastUsedDay: lastUsedDay,
                useCount: useCount,
                rng: rng,
              );
        if (meal == null) continue;

        meals.add(meal);
        for (final c in meal.components) {
          weekIngredients.addAll(c.recipe.ingredientIds);
          lastUsedDay[c.recipe.id] = d;
          useCount[c.recipe.id] = (useCount[c.recipe.id] ?? 0) + 1;
        }

        carry = _dampCarry(
            carry + (slotTarget - meal.nutrients(ingredients)), dayTarget);
      }

      days.add(DayPlan(d, meals));
      carry = _dampCarry(carry, dayTarget, dayBoundary: true);
    }

    return WeekPlan(days: days, seed: seed, generatedAt: DateTime.now());
  }

  /// Keep the carry within a sane band so one odd meal cannot distort the week.
  Nutrients _dampCarry(Nutrients c, Nutrients dayTarget,
      {bool dayBoundary = false}) {
    final limit = dayBoundary ? 0.15 : 0.25;
    double cl(double v, double t) => v.clamp(-t * limit, t * limit).toDouble();
    return Nutrients(
      kcal: cl(c.kcal, dayTarget.kcal),
      protein: cl(c.protein, dayTarget.protein),
      fat: cl(c.fat, dayTarget.fat),
      carb: cl(c.carb, dayTarget.carb),
      fibre: cl(c.fibre, dayTarget.fibre),
      iron: cl(c.iron, dayTarget.iron),
      calcium: cl(c.calcium, dayTarget.calcium),
    );
  }

  /// Breakfast and snacks: one `complete` dish, scaled toward the slot's energy.
  PlannedMeal? _planSingleDish({
    required MealType slot,
    required Nutrients slotTarget,
    required double portions,
    required int dayIndex,
    required bool isWeekend,
    required Set<String> weekIngredients,
    required Map<String, int> lastUsedDay,
    required Map<String, int> useCount,
    required math.Random rng,
  }) {
    final cands = _candidates(slot, RecipeRole.complete);
    if (cands.isEmpty) return null;

    Recipe? best;
    var bestServings = 0.0;
    var bestCost = double.infinity;

    for (final r in cands) {
      final per = _perServing(r);
      final servings = _solveServings(
        targetKcal: slotTarget.kcal,
        perServingKcal: per.kcal,
        lo: portions * 0.6,
        hi: portions * 1.8,
        granularity: 4,
      );
      if (servings <= 0) continue;
      final cost = _nutrientCost(per * servings, slotTarget) +
          _recipePenalty(
            r,
            dayIndex: dayIndex,
            isWeekend: isWeekend,
            weekIngredients: weekIngredients,
            lastUsedDay: lastUsedDay,
            useCount: useCount,
          ) +
          rng.nextDouble() * weights.jitter;
      if (cost < bestCost) {
        bestCost = cost;
        best = r;
        bestServings = servings;
      }
    }

    if (best == null) return null;
    return PlannedMeal(slot, [PlannedComponent(best, bestServings)]);
  }

  /// Lunch and dinner: protein main + staple, optionally a sabzi and a side.
  PlannedMeal? _planThali({
    required MealType slot,
    required Nutrients slotTarget,
    required double portions,
    required int dayIndex,
    required bool isWeekend,
    required Set<String> weekIngredients,
    required Map<String, int> lastUsedDay,
    required Map<String, int> useCount,
    required math.Random rng,
  }) {
    final mains = _candidates(slot, RecipeRole.main);
    final staples = _candidates(slot, RecipeRole.staple);
    if (mains.isEmpty) return null;

    final sabziOptions = <Recipe?>[null, ..._candidates(slot, RecipeRole.sabzi)];
    final sideOptions = <Recipe?>[null, ..._candidates(slot, RecipeRole.side)];

    List<PlannedComponent>? best;
    var bestCost = double.infinity;

    double penaltyOf(Recipe r) => _recipePenalty(
          r,
          dayIndex: dayIndex,
          isWeekend: isWeekend,
          weekIngredients: weekIngredients,
          lastUsedDay: lastUsedDay,
          useCount: useCount,
        );

    // Penalties depend only on which recipes are chosen, never on portion size,
    // so they are computed once per recipe and accumulated as the loops descend.
    final staplePenalty = {for (final r in staples) r.id: penaltyOf(r)};
    final sabziPenalty = {
      for (final r in sabziOptions)
        if (r != null) r.id: penaltyOf(r)
    };
    final sidePenalty = {
      for (final r in sideOptions)
        if (r != null) r.id: penaltyOf(r)
    };

    for (final main in mains) {
      final mainPer = _perServing(main);
      final mainPen = penaltyOf(main);

      for (final mainScale in _mainPortionScales) {
        final mainServings = _snap(portions * mainScale, 4);
        if (mainServings <= 0) continue;
        final mainN = mainPer * mainServings;

        for (final sabzi in sabziOptions) {
          final sabziServings = sabzi == null ? 0.0 : portions;
          final sabziN =
              sabzi == null ? Nutrients.zero : _perServing(sabzi) * sabziServings;
          final withSabziPen =
              mainPen + (sabzi == null ? 0.0 : sabziPenalty[sabzi.id]!);

          for (final side in sideOptions) {
            final sideServings = side == null ? 0.0 : portions;
            final sideN =
                side == null ? Nutrients.zero : _perServing(side) * sideServings;
            final withSidePen =
                withSabziPen + (side == null ? 0.0 : sidePenalty[side.id]!);

            final beforeStaple = mainN + sabziN + sideN;

            void consider(Recipe? staple, double stapleServings) {
              final n = staple == null
                  ? beforeStaple
                  : beforeStaple + _perServing(staple) * stapleServings;
              final cost = _nutrientCost(n, slotTarget) +
                  withSidePen +
                  (staple == null ? 0.0 : staplePenalty[staple.id]!) +
                  rng.nextDouble() * weights.jitter;
              if (cost < bestCost) {
                bestCost = cost;
                best = [
                  PlannedComponent(main, mainServings),
                  if (staple != null && stapleServings > 0)
                    PlannedComponent(staple, stapleServings),
                  if (sabzi != null) PlannedComponent(sabzi, sabziServings),
                  if (side != null) PlannedComponent(side, sideServings),
                ];
              }
            }

            if (staples.isEmpty) {
              consider(null, 0);
              continue;
            }
            for (final staple in staples) {
              final full = _solveServings(
                targetKcal: slotTarget.kcal - beforeStaple.kcal,
                perServingKcal: _perServing(staple).kcal,
                lo: 0,
                hi: portions * 4,
                granularity: 2,
              );
              for (final ss in _stapleScales) {
                consider(staple, _snap(full * ss, 2));
              }
            }
          }
        }
      }
    }

    final chosen = best;
    if (chosen == null) return null;
    return PlannedMeal(slot, chosen);
  }

  /// Portion count that best matches [targetKcal], clamped and rounded to a
  /// usable kitchen granularity.
  double _solveServings({
    required double targetKcal,
    required double perServingKcal,
    required double lo,
    required double hi,
    required int granularity,
  }) {
    if (perServingKcal <= 0) return 0;
    final s = (targetKcal / perServingKcal).clamp(lo, hi).toDouble();
    return _snap(s, granularity);
  }

  /// Cost contributed by a single recipe: repetition, shopping-list growth,
  /// preferences and weekday effort.
  ///
  /// None of these depend on the portion sizes being searched, so this is
  /// computed once per recipe per slot and reused across the whole search
  /// rather than recomputed in the innermost loop.
  double _recipePenalty(
    Recipe r, {
    required int dayIndex,
    required bool isWeekend,
    required Set<String> weekIngredients,
    required Map<String, int> lastUsedDay,
    required Map<String, int> useCount,
  }) {
    final st = _static[r.id]!;
    var cost = 0.0;

    // Repetition: strongly discourage repeats within two days, mildly
    // discourage anything already used this week.
    final last = lastUsedDay[r.id];
    if (last != null) {
      final gap = dayIndex - last;
      if (gap <= 1) {
        cost += weights.repetition * 1.5;
      } else if (gap <= 2) {
        cost += weights.repetition * 0.7;
      }
      cost += weights.repetition * 0.25 * (useCount[r.id] ?? 0);
    }

    // Shopping-list compactness: ingredients not already needed this week cost
    // extra, nudging the week toward a shorter, cheaper list.
    if (st.ids.isNotEmpty) {
      var fresh = 0;
      for (final id in st.ids) {
        if (!weekIngredients.contains(id)) fresh++;
      }
      cost += weights.newIngredient * (fresh / st.ids.length);
    }
    cost -= weights.liked * st.likedFrac;
    cost += weights.disliked * st.dislikedFrac;

    // Long cooking is fine at the weekend, less welcome on a workday.
    if (!isWeekend && r.prepMin > 35) {
      cost += weights.weekdayPrep * ((r.prepMin - 35) / 30.0);
    }
    return cost;
  }

  /// Cost of how far a meal's nutrients land from the slot target.
  double _nutrientCost(Nutrients planned, Nutrients target) {
    double rel(double p, double t) =>
        t.abs() < 1e-6 ? 0 : (p - t).abs() / t.abs();

    // For nutrients where falling short is a real nutritional failure but
    // overshooting is merely inefficient. On a vegetarian diet some protein
    // overshoot is often the only way to reach the target at all.
    double shortBiased(double p, double t, {double overPenalty = 0.35}) {
      if (t.abs() < 1e-6) return 0;
      final short = math.max(0.0, t - p) / t;
      final over = math.max(0.0, p - t) / t;
      return short + overPenalty * over;
    }

    final cost = weights.protein * shortBiased(planned.protein, target.protein) +
        weights.kcal * rel(planned.kcal, target.kcal) +
        weights.fat * rel(planned.fat, target.fat) +
        weights.carb * rel(planned.carb, target.carb) +
        weights.fibre *
            shortBiased(planned.fibre, target.fibre, overPenalty: 0.15) +
        // Dietary iron and calcium from food carry no meaningful excess risk,
        // so only the shortfall is penalised.
        weights.iron * shortBiased(planned.iron, target.iron, overPenalty: 0.0) +
        weights.calcium *
            shortBiased(planned.calcium, target.calcium, overPenalty: 0.0);

    return cost;
  }
}

/// Generate a plan, then re-run with heavier weighting on whichever of protein,
/// iron or calcium is still short, until the week is within tolerance.
///
/// The greedy pass optimises each slot locally, which can leave the week a few
/// percent short. This closes that gap without abandoning the rest of the
/// objective.
WeekPlan generateBalancedWeek({
  required Profile profile,
  required List<Recipe> recipes,
  required Map<String, Ingredient> ingredients,
  int seed = 0,
  double tolerance = 0.03,
  double microTolerance = 0.15,
  int maxPasses = 6,
}) {
  final weeklyTarget = householdWeeklyTargets(profile);
  var weights = const ScoreWeights();

  WeekPlan? bestPlan;
  var bestPenalty = double.infinity;

  for (var pass = 0; pass < maxPasses; pass++) {
    final plan = MealPlanner(
      profile: profile,
      recipes: recipes,
      ingredients: ingredients,
      weights: weights,
    ).generate(seed: seed + pass);

    final got = plan.nutrients(ingredients);

    double shortfall(double g, double t) =>
        t <= 0 ? 0 : math.max(0.0, (t - g) / t);

    final pShort = shortfall(got.protein, weeklyTarget.protein);
    final iShort = shortfall(got.iron, weeklyTarget.iron);
    final cShort = shortfall(got.calcium, weeklyTarget.calcium);

    // Protein dominates the penalty; micronutrients matter but should not
    // wreck an otherwise good week.
    final penalty = pShort * 3 + iShort + cShort;
    if (penalty < bestPenalty) {
      bestPenalty = penalty;
      bestPlan = plan;
    }
    if (pShort <= tolerance &&
        iShort <= microTolerance &&
        cShort <= microTolerance) {
      return bestPlan!;
    }

    weights = weights.copyWith(
      protein: pShort > tolerance ? weights.protein * 1.6 : weights.protein,
      iron: iShort > microTolerance ? weights.iron * 1.5 : weights.iron,
      calcium: cShort > microTolerance ? weights.calcium * 1.5 : weights.calcium,
    );
  }

  return bestPlan!;
}
