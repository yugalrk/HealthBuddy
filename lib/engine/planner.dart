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
/// Two things outside nutrition shape every choice. Foods a household member
/// gives up on a day of the week are never cooked that day. And the planner
/// keeps a [StockLedger] as it goes, so it cooks perishables while they are
/// still good, reaches for what is already open before starting a new pack,
/// and avoids needing a shop outside the household's rhythm.
///
/// The planner is deterministic given a seed, which makes it unit-testable and
/// makes "regenerate" reproducible.
library;

import 'dart:math' as math;

import '../models/food.dart';
import '../models/plan.dart';
import '../models/profile.dart';
import 'stock.dart';
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
    this.useStock = 0.8,
    this.waste = 1.6,
    this.topUp = 1.5,
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

  /// Reward for cooking with a perishable already in the kitchen, weighted
  /// towards stock that would otherwise go off by tomorrow.
  final double useStock;

  /// Cost of opening a perishable pack whose remainder may not get used.
  final double waste;

  /// Cost of needing a shop the household does not usually make.
  final double topUp;

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
        useStock: useStock,
        waste: waste,
        topUp: topUp,
      );
}

/// Where to pick up a week that is already under way.
///
/// Days before [fromDay] have happened and are kept as they were. The rest are
/// planned again, starting from what is actually left in the kitchen and
/// aiming to make up part of what the household fell short on so far.
class PlanResume {
  const PlanResume({
    required this.fromDay,
    required this.keptDays,
    required this.eatenSoFar,
    required this.stock,
    this.dayAdjust = Nutrients.zero,
  });

  final int fromDay;
  final List<DayPlan> keptDays;

  /// What the household actually ate on the kept days.
  final Nutrients eatenSoFar;

  /// A fresh ledger holding what is in the kitchen at the start of [fromDay].
  /// A factory, because each planning pass needs its own copy.
  final StockLedger Function() stock;

  /// Added to each remaining day's target.
  final Nutrients dayAdjust;
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
    this.startWeekday = 0,
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

  /// Weekday of day 0, where 0 = Monday.
  final int startWeekday;

  final Map<String, _RecipeStatic> _static = {};
  final Map<(MealType, RecipeRole, int), List<Recipe>> _candidateCache = {};
  final Map<int, Set<String>> _excludedCache = {};

  /// Ingredients nobody may be served on [weekday], because someone in the
  /// household gives them up that day. Meals are cooked once for everyone, so
  /// one person's observance shapes the whole table.
  Set<String> excludedOn(int weekday) => _excludedCache[weekday] ??= {
        for (final rule in profile.rulesOn(weekday)) ...[
          ...rule.ingredients,
          for (final ing in ingredients.values)
            if (rule.groups.any((g) => g.covers(ing))) ing.id,
        ],
      };

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
  ///
  /// Day observances are never relaxed: they are a matter of faith, not taste.
  List<Recipe> _candidates(MealType slot, RecipeRole role, int weekday) =>
      _candidateCache[(slot, role, weekday)] ??= () {
        final banned = excludedOn(weekday);
        bool allowed(Recipe r) =>
            r.role == role &&
            r.slots.contains(slot) &&
            (banned.isEmpty || !r.ingredientIds.any(banned.contains));
        final strict = recipes.where(allowed).toList(growable: false);
        if (strict.isNotEmpty || role == RecipeRole.sabzi ||
            role == RecipeRole.side) {
          // Sabzis and sides are optional, so an empty strict list is fine.
          return strict;
        }
        final lenient = _lenient.where(allowed).toList(growable: false);
        if (lenient.isNotEmpty) relaxedRoles.add(role);
        return lenient;
      }();

  Nutrients _perServing(Recipe r) => _static[r.id]!.perServing;

  WeekPlan generate({int seed = 0, PlanResume? resume}) {
    final rng = math.Random(seed);
    final dayTarget = householdDailyTargets(profile);
    final portions = householdPortions(profile);
    final shares = mealEnergyShares(includeSnacks: profile.includeSnacks);
    final fromDay = resume?.fromDay ?? 0;
    final stock = resume?.stock() ??
        StockLedger(ingredients: ingredients, profile: profile);
    final todayTarget = dayTarget + (resume?.dayAdjust ?? Nutrients.zero);

    // Ingredients already committed to this week - reusing them keeps the
    // shopping list short, so they score cheaper than introducing new ones.
    final weekIngredients = <String>{...profile.pantry};
    final lastUsedDay = <String, int>{};
    final useCount = <String, int>{};

    final days = <DayPlan>[];
    var carry = Nutrients.zero;

    void record(PlannedMeal meal, int d) {
      for (final c in meal.components) {
        weekIngredients.addAll(c.recipe.ingredientIds);
        lastUsedDay[c.recipe.id] = d;
        useCount[c.recipe.id] = (useCount[c.recipe.id] ?? 0) + 1;
      }
    }

    for (var d = 0; d < fromDay; d++) {
      final kept = resume!.keptDays[d];
      for (final m in kept.meals) {
        record(m, d);
      }
      days.add(kept);
    }

    for (var d = fromDay; d < 7; d++) {
      final meals = <PlannedMeal>[];
      final weekday = (startWeekday + d) % 7;
      final isWeekend = weekday >= 5;

      for (final slot in _mealOrder) {
        final share = shares[slot];
        if (share == null) continue;

        // Apply part of the accumulated carry to this slot, so corrections are
        // spread across meals rather than dumped on the next one.
        final slotTarget = todayTarget * share + carry * (0.5 * share / 0.30);

        final meal = slot == MealType.breakfast || slot == MealType.snack
            ? _planSingleDish(
                slot: slot,
                slotTarget: slotTarget,
                portions: portions,
                dayIndex: d,
                weekday: weekday,
                isWeekend: isWeekend,
                stock: stock,
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
                weekday: weekday,
                isWeekend: isWeekend,
                stock: stock,
                weekIngredients: weekIngredients,
                lastUsedDay: lastUsedDay,
                useCount: useCount,
                rng: rng,
              );
        if (meal == null) continue;

        meals.add(meal);
        record(meal, d);
        meal.ingredientQuantities().forEach((id, q) => stock.use(id, q, d));

        carry = _dampCarry(
            carry + (slotTarget - meal.nutrients(ingredients)), dayTarget);
      }

      days.add(DayPlan(d, meals, weekday: weekday));
      stock.endDay(d);
      carry = _dampCarry(carry, dayTarget, dayBoundary: true);
    }

    return WeekPlan(
      days: days,
      seed: seed,
      generatedAt: DateTime.now(),
      startWeekday: startWeekday,
    );
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
    required int weekday,
    required bool isWeekend,
    required StockLedger stock,
    required Set<String> weekIngredients,
    required Map<String, int> lastUsedDay,
    required Map<String, int> useCount,
    required math.Random rng,
  }) {
    final cands = _candidates(slot, RecipeRole.complete, weekday);
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
            stock: stock,
            portions: portions,
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
    required int weekday,
    required bool isWeekend,
    required StockLedger stock,
    required Set<String> weekIngredients,
    required Map<String, int> lastUsedDay,
    required Map<String, int> useCount,
    required math.Random rng,
  }) {
    final mains = _candidates(slot, RecipeRole.main, weekday);
    final staples = _candidates(slot, RecipeRole.staple, weekday);
    if (mains.isEmpty) return null;

    final sabziOptions = <Recipe?>[
      null,
      ..._candidates(slot, RecipeRole.sabzi, weekday),
    ];
    final sideOptions = <Recipe?>[
      null,
      ..._candidates(slot, RecipeRole.side, weekday),
    ];

    List<PlannedComponent>? best;
    var bestCost = double.infinity;

    double penaltyOf(Recipe r) => _recipePenalty(
          r,
          dayIndex: dayIndex,
          isWeekend: isWeekend,
          stock: stock,
          portions: portions,
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
    required StockLedger stock,
    required double portions,
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
    return cost + _stockCost(r, portions, dayIndex, stock);
  }

  /// Cost of what cooking [r] on [day] does to the kitchen.
  ///
  /// Using up perishables already bought is rewarded, most of all when they
  /// would otherwise go off by tomorrow. Opening a perishable pack costs in
  /// proportion to the remainder, less so when there are days left to use it.
  /// Needing an extra shop costs once per recipe.
  ///
  /// Quantities are taken at the household's standard portion. The main dish's
  /// portion varies a little in the search, but not enough to change which
  /// packs get opened.
  double _stockCost(Recipe r, double portions, int day, StockLedger stock) {
    var cost = 0.0;
    var topUp = false;
    final scale = portions / r.servings;
    for (final l in r.lines) {
      if (!stock.tracks(l.ingredientId)) continue;
      final ing = ingredients[l.ingredientId]!;
      final q = l.qty * scale;
      if (q <= 0) continue;
      final quote = stock.quote(l.ingredientId, q, day);
      if (quote.topUp) topUp = true;
      if (!ing.perishable) continue;
      cost -= weights.useStock *
          (0.4 * quote.fromStock + 0.6 * quote.fromExpiring) /
          q;
      if (quote.leftover > 0) {
        final daysLeft = quote.leftoverGoodUntil - day;
        cost += weights.waste *
            (quote.leftover / ing.packSize) /
            (1 + 0.5 * math.max(0, daysLeft));
      }
    }
    if (topUp) cost += weights.topUp;
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

/// How far a week falls short of its targets, as one number: protein
/// dominates, iron and calcium matter, and energy counts once it strays more
/// than 3% either way.
double weekShortfall(Nutrients got, Nutrients target) {
  double shortfall(double g, double t) =>
      t <= 0 ? 0 : math.max(0.0, (t - g) / t);
  final kcalDev = target.kcal <= 0 ? 0.0 : (got.kcal / target.kcal - 1).abs();
  return shortfall(got.protein, target.protein) * 3 +
      shortfall(got.iron, target.iron) +
      shortfall(got.calcium, target.calcium) +
      math.max(0.0, kcalDev - 0.03) * 2;
}

/// Generate a plan, then re-run with heavier weighting on whichever of protein,
/// iron or calcium is still short, until the week is within tolerance.
///
/// The greedy pass optimises each slot locally, which can leave the week a few
/// percent short. This closes that gap without abandoning the rest of the
/// objective. The chosen week then goes through [reduceSpoilage].
///
/// With [resume], only the days from [PlanResume.fromDay] are planned, and the
/// week is judged on what was actually eaten before them plus the new plan.
WeekPlan generateBalancedWeek({
  required Profile profile,
  required List<Recipe> recipes,
  required Map<String, Ingredient> ingredients,
  int seed = 0,
  int startWeekday = 0,
  PlanResume? resume,
  double tolerance = 0.03,
  double microTolerance = 0.15,
  int maxPasses = 6,
}) {
  final weeklyTarget = householdWeeklyTargets(profile);
  var weights = const ScoreWeights();

  WeekPlan? bestPlan;
  var bestPenalty = double.infinity;

  final fromDay = resume?.fromDay ?? 0;
  Nutrients weekGot(WeekPlan plan) =>
      (resume?.eatenSoFar ?? Nutrients.zero) +
      Nutrients.sum(plan.days
          .where((d) => d.dayIndex >= fromDay)
          .map((d) => d.nutrients(ingredients)));

  for (var pass = 0; pass < maxPasses; pass++) {
    final plan = MealPlanner(
      profile: profile,
      recipes: recipes,
      ingredients: ingredients,
      weights: weights,
      startWeekday: startWeekday,
    ).generate(seed: seed + pass, resume: resume);

    final got = weekGot(plan);

    double shortfall(double g, double t) =>
        t <= 0 ? 0 : math.max(0.0, (t - g) / t);

    final pShort = shortfall(got.protein, weeklyTarget.protein);
    final iShort = shortfall(got.iron, weeklyTarget.iron);
    final cShort = shortfall(got.calcium, weeklyTarget.calcium);

    // Protein dominates the penalty; micronutrients matter but should not
    // wreck an otherwise good week. Energy counts too: a pass that reaches
    // protein by piling on 15% more food is not the better week.
    final penalty = weekShortfall(got, weeklyTarget);
    if (penalty < bestPenalty) {
      bestPenalty = penalty;
      bestPlan = plan;
    }
    if (pShort <= tolerance &&
        iShort <= microTolerance &&
        cShort <= microTolerance) {
      break;
    }

    weights = weights.copyWith(
      protein: pShort > tolerance ? weights.protein * 1.6 : weights.protein,
      iron: iShort > microTolerance ? weights.iron * 1.5 : weights.iron,
      calcium: cShort > microTolerance ? weights.calcium * 1.5 : weights.calcium,
    );
  }

  return reduceSpoilage(
    plan: bestPlan!,
    fromDay: fromDay,
    ingredients: ingredients,
    judge: (p) => weekShortfall(weekGot(p), weeklyTarget),
    simulate: (p) => resume == null
        ? StockLedger.replay(
            plan: p, ingredients: ingredients, profile: profile)
        : _replayFrom(p, resume, ingredients),
  );
}

/// Run the planned days of [plan] through the kitchen as it stood at
/// [PlanResume.fromDay].
StockLedger _replayFrom(
    WeekPlan plan, PlanResume resume, Map<String, Ingredient> ingredients) {
  final ledger = resume.stock();
  for (final day in plan.days.where((d) => d.dayIndex >= resume.fromDay)) {
    for (final m in day.meals) {
      m.ingredientQuantities().forEach((id, q) {
        ledger.use(id, q, day.dayIndex);
      });
    }
    ledger.endDay(day.dayIndex);
  }
  return ledger;
}

/// Adjust portions so food does not go off before it is eaten.
///
/// Buying whole packs leaves remainders, and the greedy planner cannot always
/// find a later meal to use them in before they spoil. This works through
/// what the plan would waste, largest first, and tries two fixes for each:
///
/// * **use it up** — a larger portion of a dish that already uses the
///   ingredient while it is still good: up to 2.5 times the planned portion
///   for a sabzi or side, 1.6 times for anything else;
/// * **buy one pack fewer** — when the overflow into the last pack is small,
///   trim every dish that uses the ingredient in that window so it fits.
///
/// A change is kept only if it cuts waste and leaves the week's nutrition no
/// worse, as scored by [judge], than a hair's breadth. Days before [fromDay]
/// have already happened and are never touched.
WeekPlan reduceSpoilage({
  required WeekPlan plan,
  required int fromDay,
  required Map<String, Ingredient> ingredients,
  required double Function(WeekPlan) judge,
  required StockLedger Function(WeekPlan) simulate,
  int maxSteps = 30,
}) {
  final original = <(int, int, int), double>{};
  for (final d in plan.days) {
    for (var m = 0; m < d.meals.length; m++) {
      for (var c = 0; c < d.meals[m].components.length; c++) {
        original[(d.dayIndex, m, c)] = d.meals[m].components[c].servings;
      }
    }
  }

  var current = plan;
  var ledger = simulate(current);
  var waste = ledger.wasteScore;
  var score = judge(current);

  for (var step = 0; step < maxSteps && waste > 0.02; step++) {
    WeekPlan? accepted;
    final spoils = [...ledger.spoiled]..sort((a, b) =>
        (b.qty / ingredients[b.ingredientId]!.packSize)
            .compareTo(a.qty / ingredients[a.ingredientId]!.packSize));

    for (final sp in spoils) {
      final uses = <(int, int, int, double)>[];
      for (final d in current.days) {
        if (d.dayIndex < fromDay ||
            d.dayIndex < sp.boughtDay ||
            d.dayIndex > sp.goodUntil) {
          continue;
        }
        for (var m = 0; m < d.meals.length; m++) {
          final comps = d.meals[m].components;
          for (var c = 0; c < comps.length; c++) {
            if (comps[c].recipe.role == RecipeRole.staple) continue;
            final q = comps[c].ingredientQuantities()[sp.ingredientId];
            if (q != null && q > 0) uses.add((d.dayIndex, m, c, q));
          }
        }
      }
      if (uses.isEmpty) continue;

      final candidates = <WeekPlan>[];

      // Use it up: grow one dish.
      for (final (d, m, c, q) in uses) {
        final comp = current.days[d].meals[m].components[c];
        // A bigger bowl of sabzi is easy to eat; a bigger bowl of dal less so.
        final growth = switch (comp.recipe.role) {
          RecipeRole.sabzi || RecipeRole.side => 2.5,
          _ => 1.6,
        };
        final cap = original[(d, m, c)]! * growth;
        final grown =
            _snap(math.min(cap, comp.servings * (1 + sp.qty / q)), 4);
        if (grown > comp.servings) {
          candidates.add(_withServings(current, {(d, m, c): grown}));
        }
      }

      // Buy one pack fewer: trim every dish in the window.
      final ing = ingredients[sp.ingredientId]!;
      final used = uses.fold(0.0, (a, u) => a + u.$4);
      final overflow = used - (used / ing.packSize).floor() * ing.packSize;
      if (overflow > 0 && overflow <= used * 0.3 && used > ing.packSize) {
        final f = 1 - (overflow + 0.5) / used;
        final trimmed = <(int, int, int), double>{};
        var ok = true;
        for (final (d, m, c, _) in uses) {
          final comp = current.days[d].meals[m].components[c];
          // Round down so the trimmed dishes really fit in the packs.
          final s = (comp.servings * f * 4).floor() / 4;
          if (s < original[(d, m, c)]! * 0.7 || s <= 0) ok = false;
          trimmed[(d, m, c)] = s;
        }
        if (ok) candidates.add(_withServings(current, trimmed));
      }

      for (final cand in candidates) {
        final l = simulate(cand);
        final j = judge(cand);
        if (l.wasteScore < waste - 0.02 && j <= score + 0.01) {
          accepted = cand;
          ledger = l;
          waste = l.wasteScore;
          score = math.min(score, j);
          break;
        }
      }
      if (accepted != null) break;
    }

    if (accepted == null) break;
    current = accepted;
  }
  return current;
}

WeekPlan _withServings(
    WeekPlan plan, Map<(int, int, int), double> servings) {
  return WeekPlan(
    seed: plan.seed,
    generatedAt: plan.generatedAt,
    startWeekday: plan.startWeekday,
    days: [
      for (final d in plan.days)
        DayPlan(
          d.dayIndex,
          [
            for (var m = 0; m < d.meals.length; m++)
              PlannedMeal(d.meals[m].type, [
                for (var c = 0; c < d.meals[m].components.length; c++)
                  servings.containsKey((d.dayIndex, m, c))
                      ? d.meals[m].components[c]
                          .withServings(servings[(d.dayIndex, m, c)]!)
                      : d.meals[m].components[c],
              ]),
          ],
          weekday: d.weekday,
        ),
    ],
  );
}
