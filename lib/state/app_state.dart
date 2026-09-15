/// Application state.
///
/// Deliberately a plain [ChangeNotifier] with no state-management package: the
/// app has one profile, one week plan and a set of ticked shopping items, and
/// that does not justify a dependency.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../data/food_data.dart';
import '../data/repositories/repositories.dart';
import '../engine/planner.dart';
import '../engine/shopping_list.dart';
import '../engine/targets.dart';
import '../models/food.dart';
import '../models/plan.dart';
import '../models/profile.dart';

enum LoadState { loading, onboarding, ready }

class AppState extends ChangeNotifier {
  AppState({
    ProfileRepository? profileRepo,
    PlanRepository? planRepo,
    this.useBackgroundIsolate = true,
  })  : _profileRepo = profileRepo ?? SharedPrefsProfileRepository(),
        _planRepo = planRepo ?? SharedPrefsPlanRepository();

  final ProfileRepository _profileRepo;
  final PlanRepository _planRepo;

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

  WeekPlan? _plan;
  WeekPlan? get plan => _plan;

  SavedWeek? _saved;
  Set<String> get checkedItems => _saved?.checkedItems ?? const {};

  bool _generating = false;
  bool get generating => _generating;

  Object? _error;
  Object? get error => _error;

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
      if (_saved != null) {
        await _regenerateFromSeed(_saved!.seed);
      }
      _state = LoadState.ready;
    } catch (e) {
      _error = e;
      _state = LoadState.onboarding;
    }
    notifyListeners();
  }

  Future<void> completeOnboarding(Profile p) async {
    _profile = p;
    await _profileRepo.save(p);
    await generateNewWeek();
    _state = LoadState.ready;
    notifyListeners();
  }

  Future<void> updateProfile(Profile p) async {
    _profile = p;
    await _profileRepo.save(p);
    notifyListeners();
    // The plan is derived from the profile, so it must be rebuilt.
    await generateNewWeek();
  }

  /// Plan generation takes a few hundred milliseconds, which is long enough to
  /// drop frames, so it runs off the UI isolate.
  Future<void> generateNewWeek({int? seed}) async {
    if (_profile == null) return;
    _generating = true;
    notifyListeners();

    final useSeed = seed ?? DateTime.now().millisecondsSinceEpoch % 100000;
    await _regenerateFromSeed(useSeed);

    _saved = SavedWeek(
      seed: useSeed,
      generatedAt: DateTime.now(),
      checkedItems: const {},
    );
    await _planRepo.save(_saved!);

    _generating = false;
    notifyListeners();
  }

  Future<void> _regenerateFromSeed(int seed) async {
    final args = _PlanArgs(
      profile: _profile!,
      food: _food!,
      seed: seed,
    );
    _plan = (kIsWeb || !useBackgroundIsolate)
        ? _generatePlan(args)
        : await compute(_generatePlan, args);
  }

  void toggleChecked(String ingredientId) {
    if (_saved == null) return;
    final next = {..._saved!.checkedItems};
    if (!next.remove(ingredientId)) next.add(ingredientId);
    _saved = _saved!.copyWith(checkedItems: next);
    _planRepo.save(_saved!);
    notifyListeners();
  }

  Future<void> resetAll() async {
    await _profileRepo.clear();
    await _planRepo.clear();
    _profile = null;
    _plan = null;
    _saved = null;
    _state = LoadState.onboarding;
    notifyListeners();
  }

  // ---- Derived values -------------------------------------------------

  Nutrients get dailyTargets => householdDailyTargets(profile);
  Nutrients get weeklyTargets => householdWeeklyTargets(profile);
  Nutrients? get weeklyPlanned => _plan?.nutrients(food.ingredients);

  /// Ingredients the household asked to avoid that the plan could not exclude.
  Set<String> get unavoidable =>
      _plan?.avoidedButPresent(profile.disliked) ?? const {};

  ShoppingList? get shoppingList => _plan == null
      ? null
      : buildShoppingList(
          plan: _plan!,
          ingredients: food.ingredients,
          profile: profile,
        );
}

class _PlanArgs {
  const _PlanArgs({
    required this.profile,
    required this.food,
    required this.seed,
  });
  final Profile profile;
  final FoodData food;
  final int seed;
}

/// Top-level so it can run in a background isolate.
WeekPlan _generatePlan(_PlanArgs a) => generateBalancedWeek(
      profile: a.profile,
      recipes: a.food.recipes,
      ingredients: a.food.ingredients,
      seed: a.seed,
    );
