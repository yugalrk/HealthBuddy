/// Application state.
///
/// Deliberately a plain [ChangeNotifier] with no state-management package: the
/// app has one profile, one week in progress and a set of ticked shopping
/// items, and that does not justify a dependency.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../data/food_data.dart';
import '../data/repositories/repositories.dart';
import '../engine/adapt.dart';
import '../engine/day_score.dart';
import '../engine/planner.dart';
import '../engine/shopping_list.dart';
import '../engine/stock.dart';
import '../engine/targets.dart';
import '../models/food.dart';
import '../models/plan.dart';
import '../models/profile.dart';

enum LoadState { loading, onboarding, ready }

/// From this hour the app asks how the day went.
const int feedbackHour = 18;

class AppState extends ChangeNotifier {
  AppState({
    ProfileRepository? profileRepo,
    PlanRepository? planRepo,
    ScoreRepository? scoreRepo,
    this.useBackgroundIsolate = true,
    DateTime Function()? clock,
  })  : _profileRepo = profileRepo ?? SharedPrefsProfileRepository(),
        _planRepo = planRepo ?? SharedPrefsPlanRepository(),
        _scoreRepo = scoreRepo ?? SharedPrefsScoreRepository(),
        _clock = clock ?? DateTime.now;

  final ProfileRepository _profileRepo;
  final PlanRepository _planRepo;
  final ScoreRepository _scoreRepo;
  final DateTime Function() _clock;

  /// Whether plan generation is pushed onto a background isolate.
  ///
  /// Always true in the app, so the ~600 ms of work does not drop frames.
  /// Tests set it false: `flutter_test` drives a fake clock, and an isolate
  /// round-trip never completes under it.
  final bool useBackgroundIsolate;

  LoadState _state = LoadState.loading;
  LoadState get state => _state;

  FoodData? _food;
  FoodData get food => _food!;

  Profile? _profile;
  Profile get profile => _profile!;
  bool get hasProfile => _profile != null;

  WeekProgress? _progress;
  WeekProgress? get progress => _progress;
  WeekPlan? get plan => _progress?.plan;

  SavedWeek? _saved;
  Set<String> get checkedItems => _saved?.checkedItems ?? const {};

  bool _generating = false;
  bool get generating => _generating;

  /// The most recent adjustment made from feedback, for the Plan screen to
  /// explain. Cleared when a new week is planned.
  WeekAdjustment? _lastAdaptation;
  WeekAdjustment? get lastAdaptation => _lastAdaptation;

  Object? _error;
  Object? get error => _error;

  ScoreLog _scores = ScoreLog();

  /// Every day scored from the evening check-in.
  ScoreLog get scores => _scores;

  /// Today, at midnight.
  DateTime get today {
    final n = _clock();
    return DateTime(n.year, n.month, n.day);
  }

  Future<void> init() async {
    try {
      final ingredientsJson =
          await rootBundle.loadString('assets/seed/ingredients.json');
      final recipesJson =
          await rootBundle.loadString('assets/seed/recipes.json');
      _food = FoodData.parse(
        ingredientsJson: ingredientsJson,
        recipesJson: recipesJson,
      );

      assert(() {
        final issues = _food!.validate();
        if (issues.isNotEmpty) {
          debugPrint('Seed data issues:\n${issues.join('\n')}');
        }
        return issues.isEmpty;
      }(), 'Bundled food data failed validation');

      _profile = await _profileRepo.load();
      if (_profile == null) {
        _state = LoadState.onboarding;
        notifyListeners();
        return;
      }

      _saved = await _planRepo.load();
      if (_saved != null) await _restore(_saved!);
      _scores = await _scoreRepo.load();
      await _scoreReportedDays();
      _state = LoadState.ready;
    } catch (e) {
      _error = e;
      _state = LoadState.onboarding;
    }
    notifyListeners();
  }

  Future<void> _restore(SavedWeek saved) async {
    final recipesById = {for (final r in food.recipes) r.id: r};
    final stored = saved.plan == null
        ? null
        : WeekPlan.fromJson(saved.plan!, recipesById);
    if (stored != null) {
      _progress = WeekProgress(
        plan: stored,
        feedback: {
          for (final f in saved.feedback)
            (f['day'] as int): DayFeedback.fromJson(f)
        },
        bought: [for (final b in saved.bought) Purchase.fromJson(b)],
        frozenThrough: saved.frozenThrough,
      );
      return;
    }
    // A week saved before plans were stored, or one whose recipes have since
    // changed: rebuild it from its seed, starting on the day it was planned.
    final plan = await _run(_generatePlan, _PlanArgs(
      profile: _profile!,
      food: _food!,
      seed: saved.seed,
      startWeekday: saved.generatedAt.weekday - 1,
    ));
    _progress = WeekProgress(plan: plan);
    _saved = saved.copyWith(plan: plan.toJson());
    await _planRepo.save(_saved!);
  }

  Future<void> completeOnboarding(Profile p) async {
    _profile = p;
    await _profileRepo.save(p);
    await generateNewWeek();
    _state = LoadState.ready;
    notifyListeners();
  }

  /// The plan is derived from the profile, so it must be rebuilt. Mid-week,
  /// only the days from today on are planned again; the days already lived
  /// through, their feedback and the shops already made are kept.
  Future<void> updateProfile(Profile p) async {
    _profile = p;
    await _profileRepo.save(p);
    notifyListeners();
    final today = todayIndex;
    if (_progress == null || today <= 0 || today > 6) {
      await generateNewWeek();
      return;
    }
    await _adapt(throughDay: today - 1, force: true);
  }

  /// Plan a fresh week starting today.
  ///
  /// Plan generation takes a few hundred milliseconds, which is long enough to
  /// drop frames, so it runs off the UI isolate.
  Future<void> generateNewWeek({int? seed}) async {
    if (_profile == null) return;
    _generating = true;
    notifyListeners();

    final now = _clock();
    final useSeed = seed ?? now.millisecondsSinceEpoch % 100000;
    final plan = await _run(_generatePlan, _PlanArgs(
      profile: _profile!,
      food: _food!,
      seed: useSeed,
      startWeekday: now.weekday - 1,
    ));
    _progress = WeekProgress(plan: plan);
    _lastAdaptation = null;

    _saved = SavedWeek(
      seed: useSeed,
      generatedAt: now,
      checkedItems: const {},
      plan: plan.toJson(),
    );
    await _planRepo.save(_saved!);

    _generating = false;
    notifyListeners();
  }

  // ---- The week in time ----------------------------------------------

  DateTime _dateOnly(DateTime t) => DateTime.utc(t.year, t.month, t.day);

  /// The date of day 0.
  DateTime get startDate => _dateOnly(_saved?.generatedAt ?? _clock());

  DateTime dateOf(int dayIndex) => startDate.add(Duration(days: dayIndex));

  /// Which day of the week today is: 0 on the day it was planned, 7 or more
  /// once it is over.
  int get todayIndex => _dateOnly(_clock()).difference(startDate).inDays;

  bool get weekOver => todayIndex > 6;

  /// The earliest day still waiting to hear how it went: any earlier day of
  /// the week, or today once it is evening.
  int? get pendingFeedbackDay {
    final p = _progress;
    if (p == null) return null;
    final today = todayIndex;
    final evening = _clock().hour >= feedbackHour;
    for (var d = 0; d <= today && d < 7; d++) {
      if (p.feedback.containsKey(d)) continue;
      if (d < today || evening) return d;
    }
    return null;
  }

  // ---- Feedback -------------------------------------------------------

  /// Record how [fb]'s day went, and adjust the rest of the week to it.
  ///
  /// Shops up to today are treated as done. When the feedback is for an
  /// earlier day, today is kept as planned — it is already under way.
  Future<void> recordFeedback(DayFeedback fb) async {
    final p = _progress;
    if (p == null) return;
    _progress = WeekProgress(
      plan: p.plan,
      feedback: {...p.feedback, fb.dayIndex: fb},
      bought: p.bought,
      frozenThrough: p.frozenThrough,
    );
    final today = todayIndex.clamp(0, 6);
    final through = fb.dayIndex > today ? fb.dayIndex : today;
    // Scored from the plan as it stood that day, before replanning.
    _scores.put(scoreFor(fb));
    await _scoreRepo.save(_scores);
    await _adapt(throughDay: through, latest: fb);
  }

  /// Your score for the day [fb] reports.
  ///
  /// The check-in is for the household, so your share of what was eaten is
  /// taken in proportion to your needs: the plan sizes everyone's portions
  /// the same way. Junk snacks are yours alone.
  DayScore scoreFor(DayFeedback fb) {
    final day = plan!.days[fb.dayIndex];
    final you = targetsForMember(profile.primary, profile.diet);
    final all = dailyTargets;
    final share = all.kcal <= 0 ? 1.0 : you.kcal / all.kcal;
    return scoreDay(
      date: dateOf(fb.dayIndex),
      eaten: fb.eaten(day, food.ingredients) * share,
      target: you,
      junkSnacks: fb.junkSnacks,
    );
  }

  /// Days reported before scoring existed get their score on first launch.
  Future<void> _scoreReportedDays() async {
    final p = _progress;
    if (p == null) return;
    var added = false;
    for (final fb in p.feedback.values) {
      if (_scores.on(dateOf(fb.dayIndex)) != null) continue;
      _scores.put(scoreFor(fb));
      added = true;
    }
    if (added) await _scoreRepo.save(_scores);
  }

  Future<void> _adapt({
    required int throughDay,
    DayFeedback? latest,
    bool force = false,
  }) async {
    _generating = true;
    notifyListeners();

    final result = await _run(_adaptWeek, _AdaptArgs(
      profile: _profile!,
      food: _food!,
      progress: _progress!,
      throughDay: throughDay,
      latest: latest,
      force: force,
    ));
    _progress = result.progress;
    if (result.replanned) _lastAdaptation = result;
    await _persistProgress();

    _generating = false;
    notifyListeners();
  }

  void dismissAdaptation() {
    _lastAdaptation = null;
    notifyListeners();
  }

  Future<void> _persistProgress() async {
    final p = _progress!;
    _saved = (_saved ??
            SavedWeek(seed: p.plan.seed, generatedAt: p.plan.generatedAt))
        .copyWith(
      plan: p.plan.toJson(),
      feedback: [for (final f in p.feedback.values) f.toJson()],
      bought: [for (final b in p.bought) b.toJson()],
      frozenThrough: p.frozenThrough,
    );
    await _planRepo.save(_saved!);
  }

  Future<R> _run<A, R>(R Function(A) fn, A args) async =>
      (kIsWeb || !useBackgroundIsolate) ? fn(args) : await compute(fn, args);

  void toggleChecked(String key) {
    if (_saved == null) return;
    final next = {..._saved!.checkedItems};
    if (!next.remove(key)) next.add(key);
    _saved = _saved!.copyWith(checkedItems: next);
    _planRepo.save(_saved!);
    notifyListeners();
  }

  /// Tick or untick several items at once.
  void setChecked(Iterable<String> keys, bool value) {
    if (_saved == null) return;
    final next = {..._saved!.checkedItems};
    value ? next.addAll(keys) : next.removeAll(keys);
    _saved = _saved!.copyWith(checkedItems: next);
    _planRepo.save(_saved!);
    notifyListeners();
  }

  Future<void> resetAll() async {
    await _profileRepo.clear();
    await _planRepo.clear();
    await _scoreRepo.clear();
    _scores = ScoreLog();
    _profile = null;
    _progress = null;
    _saved = null;
    _lastAdaptation = null;
    _state = LoadState.onboarding;
    notifyListeners();
  }

  // ---- Derived values -------------------------------------------------

  Nutrients get dailyTargets => householdDailyTargets(profile);
  Nutrients get weeklyTargets => householdWeeklyTargets(profile);

  /// The week as it is turning out: what was eaten on days with feedback,
  /// and the plan for the rest.
  Nutrients? get weeklyPlanned => _progress?.weekSoFar(food.ingredients);

  /// Ingredients the household asked to avoid that the plan could not exclude.
  Set<String> get unavoidable =>
      plan?.avoidedButPresent(profile.disliked) ?? const {};

  ShoppingList? get shoppingList {
    final p = _progress;
    if (p == null) return null;
    return buildShoppingList(
      plan: p.plan,
      ingredients: food.ingredients,
      profile: profile,
      stock: p.ledger(food.ingredients, profile),
    );
  }
}

class _PlanArgs {
  const _PlanArgs({
    required this.profile,
    required this.food,
    required this.seed,
    required this.startWeekday,
  });
  final Profile profile;
  final FoodData food;
  final int seed;
  final int startWeekday;
}

/// Top-level so it can run in a background isolate.
WeekPlan _generatePlan(_PlanArgs a) => generateBalancedWeek(
      profile: a.profile,
      recipes: a.food.recipes,
      ingredients: a.food.ingredients,
      seed: a.seed,
      startWeekday: a.startWeekday,
    );

class _AdaptArgs {
  const _AdaptArgs({
    required this.profile,
    required this.food,
    required this.progress,
    required this.throughDay,
    this.latest,
    this.force = false,
  });
  final Profile profile;
  final FoodData food;
  final WeekProgress progress;
  final int throughDay;
  final DayFeedback? latest;
  final bool force;
}

WeekAdjustment _adaptWeek(_AdaptArgs a) => adaptWeek(
      progress: a.progress,
      throughDay: a.throughDay,
      latest: a.latest,
      force: a.force,
      profile: a.profile,
      recipes: a.food.recipes,
      ingredients: a.food.ingredients,
    );
