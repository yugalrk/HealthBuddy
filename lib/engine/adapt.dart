/// Keeping the week on track once it is under way.
///
/// At the end of each day the household says how closely it followed the
/// plan. From that the app knows two things: what everyone actually ate, and
/// what is actually left in the kitchen. The rest of the week is then planned
/// again from that point — making up part of any shortfall, and cooking the
/// food that was bought but not used before it goes off.
library;

import '../models/food.dart';
import '../models/plan.dart';
import '../models/profile.dart';
import 'planner.dart';
import 'stock.dart';
import 'targets.dart';

/// How far a single day's target may be raised or lowered to make up for
/// earlier days. Past this, the extra food stops being realistic to eat; the
/// rest of the gap is left rather than forced.
const double maxDailyCatchUp = 0.20;

/// Everything known about the week so far.
class WeekProgress {
  const WeekProgress({
    required this.plan,
    this.feedback = const {},
    this.bought = const [],
    this.frozenThrough = -1,
  });

  final WeekPlan plan;
  final Map<int, DayFeedback> feedback;

  /// Shops already made, on days up to [frozenThrough].
  final List<Purchase> bought;

  /// Last day whose shops are done and whose meals are no longer replanned.
  final int frozenThrough;

  /// The kitchen, day by day: past days from what was bought and actually
  /// used, later days from the plan.
  StockLedger ledger(Map<String, Ingredient> ingredients, Profile profile) =>
      StockLedger.replay(
        plan: plan,
        ingredients: ingredients,
        profile: profile,
        feedback: feedback,
        alreadyBought: bought,
        frozenThrough: frozenThrough,
      );

  /// What was eaten on [day]: from feedback where given, otherwise the plan.
  Nutrients eatenOn(DayPlan day, Map<String, Ingredient> ingredients) =>
      feedback[day.dayIndex]?.eaten(day, ingredients) ??
      day.nutrients(ingredients);

  /// The week as it is turning out: eaten on days with feedback, planned on
  /// the rest.
  Nutrients weekSoFar(Map<String, Ingredient> ingredients) =>
      Nutrients.sum(plan.days.map((d) => eatenOn(d, ingredients)));
}

/// The outcome of adapting a week.
class WeekAdjustment {
  const WeekAdjustment({
    required this.progress,
    required this.replanned,
    this.dayAdjust = Nutrients.zero,
    this.fromDay = 7,
  });

  final WeekProgress progress;

  /// False when the plan was followed and so left as it was.
  final bool replanned;

  /// Added to each remaining day's target to make up the shortfall so far.
  final Nutrients dayAdjust;

  /// First day that was planned again.
  final int fromDay;
}

/// Fold what happened up to and including [throughDay] into the week, and
/// plan the days after it again if anything went differently.
///
/// Shops on days up to [throughDay] are fixed at what the shopping list said
/// to buy at the time. The rest of the week is replanned only when [latest] —
/// the feedback just given — says something went differently; a day that
/// went to plan changes nothing about the days after it. [force] replans
/// regardless, for when the household itself has changed.
WeekAdjustment adaptWeek({
  required WeekProgress progress,
  required int throughDay,
  DayFeedback? latest,
  bool force = false,
  required Profile profile,
  required List<Recipe> recipes,
  required Map<String, Ingredient> ingredients,
}) {
  final plan = progress.plan;
  final through = throughDay.clamp(progress.frozenThrough, 6);

  // What the household bought on the shops that have now happened. Replayed
  // against the plan as it stood, because that is the list they shopped from.
  final asListed = StockLedger.replay(
    plan: plan,
    ingredients: ingredients,
    profile: profile,
    feedback: {
      for (final e in progress.feedback.entries)
        if (e.key <= progress.frozenThrough) e.key: e.value,
    },
    alreadyBought: progress.bought,
    frozenThrough: progress.frozenThrough,
  );
  final bought = [
    for (final p in asListed.purchases)
      if (p.day <= through) p,
  ];

  final frozen = WeekProgress(
    plan: plan,
    feedback: progress.feedback,
    bought: bought,
    frozenThrough: through,
  );

  final wentDifferently = force || (latest != null && !latest.followedFully);
  if (through >= 6 || !wentDifferently) {
    return WeekAdjustment(progress: frozen, replanned: false);
  }

  final fromDay = through + 1;
  final kept = plan.days.take(fromDay).toList();
  final eaten = Nutrients.sum(kept.map((d) => frozen.eatenOn(d, ingredients)));

  final dayTarget = householdDailyTargets(profile);
  final gap = dayTarget * fromDay.toDouble() - eaten;
  final dayAdjust = _clampEach(gap * (1 / (7 - fromDay)), dayTarget);

  StockLedger kitchen() {
    final ledger = StockLedger(
      ingredients: ingredients,
      profile: profile,
      frozenThrough: through,
      alreadyBought: bought,
    );
    for (final day in kept) {
      final fb = frozen.feedback[day.dayIndex];
      final used = fb?.used(day) ?? _planned(day);
      used.forEach((id, q) => ledger.use(id, q, day.dayIndex, canBuy: false));
      ledger.endDay(day.dayIndex);
    }
    return ledger;
  }

  final replanned = generateBalancedWeek(
    profile: profile,
    recipes: recipes,
    ingredients: ingredients,
    seed: plan.seed,
    startWeekday: plan.startWeekday,
    resume: PlanResume(
      fromDay: fromDay,
      keptDays: kept,
      eatenSoFar: eaten,
      stock: kitchen,
      dayAdjust: dayAdjust,
    ),
  );

  return WeekAdjustment(
    progress: WeekProgress(
      plan: WeekPlan(
        days: replanned.days,
        seed: plan.seed,
        generatedAt: plan.generatedAt,
        startWeekday: plan.startWeekday,
      ),
      feedback: frozen.feedback,
      bought: bought,
      frozenThrough: through,
    ),
    replanned: true,
    dayAdjust: dayAdjust,
    fromDay: fromDay,
  );
}

Map<String, double> _planned(DayPlan day) {
  final out = <String, double>{};
  for (final m in day.meals) {
    m.ingredientQuantities().forEach((id, q) => out[id] = (out[id] ?? 0) + q);
  }
  return out;
}

Nutrients _clampEach(Nutrients n, Nutrients limit) {
  double c(double v, double t) =>
      v.clamp(-t * maxDailyCatchUp, t * maxDailyCatchUp).toDouble();
  return Nutrients(
    kcal: c(n.kcal, limit.kcal),
    protein: c(n.protein, limit.protein),
    fat: c(n.fat, limit.fat),
    carb: c(n.carb, limit.carb),
    fibre: c(n.fibre, limit.fibre),
    iron: c(n.iron, limit.iron),
    calcium: c(n.calcium, limit.calcium),
  );
}
