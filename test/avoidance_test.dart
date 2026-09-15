import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbuddy/data/food_data.dart';
import 'package:healthbuddy/engine/planner.dart';
import 'package:healthbuddy/engine/shopping_list.dart';
import 'package:healthbuddy/models/food.dart';
import 'package:healthbuddy/models/profile.dart';

FoodData loadSeed() => FoodData.parse(
      ingredientsJson: File('assets/seed/ingredients.json').readAsStringSync(),
      recipesJson: File('assets/seed/recipes.json').readAsStringSync(),
    );

Profile profileAvoiding(Set<String> avoid, {DietType diet = DietType.veg}) =>
    Profile(
      members: [
        const HouseholdMember(
          id: 'a',
          name: 'a',
          age: 30,
          sex: Sex.male,
          weightKg: 70,
          heightCm: 175,
          activity: ActivityLevel.moderate,
          goal: Goal.maintain,
          isPrimary: true,
        ),
      ],
      diet: diet,
      disliked: avoid,
    );

void main() {
  late FoodData data;
  setUpAll(() => data = loadSeed());

  /// Ingredients the onboarding screen actually offers as avoidable.
  List<Ingredient> userSelectable(FoodData d) => d.ingredients.values
      .where((i) => !i.pantryStaple && DietType.veg.admits(i.diet))
      .where((i) => const {
            Aisle.vegetables,
            Aisle.pulses,
            Aisle.dairy,
            Aisle.eggmeat,
            Aisle.nuts,
            Aisle.fruits,
          }.contains(i.aisle))
      .toList();

  test('every individually avoidable ingredient is actually avoided', () {
    final leaked = <String>[];
    for (final ing in userSelectable(data)) {
      final p = profileAvoiding({ing.id});
      final plan = generateBalancedWeek(
        profile: p,
        recipes: data.recipes,
        ingredients: data.ingredients,
        seed: 3,
      );
      if (plan.ingredientTotals().containsKey(ing.id)) leaked.add(ing.name);
    }
    expect(leaked, isEmpty,
        reason: 'these were marked avoid but still planned: '
            '${leaked.join(", ")}');
  });

  test('avoided ingredients never reach the shopping list', () {
    final avoid = {'onion', 'tomato', 'potato', 'curd', 'peanuts'};
    final p = profileAvoiding(avoid);
    final plan = generateBalancedWeek(
      profile: p,
      recipes: data.recipes,
      ingredients: data.ingredients,
      seed: 8,
    );
    final list = buildShoppingList(
      plan: plan,
      ingredients: data.ingredients,
      profile: p,
    );
    final listed = {
      for (final items in list.toBuy.values)
        for (final i in items) i.ingredient.id,
      for (final i in list.pantryCheck) i.ingredient.id,
    };
    expect(listed.intersection(avoid), isEmpty);
    expect(plan.avoidedButPresent(avoid), isEmpty);
  });

  test('avoiding several common vegetables at once still yields a full week',
      () {
    final p = profileAvoiding({'baingan', 'lauki', 'bhindi', 'palak', 'gobi'});
    final plan = generateBalancedWeek(
      profile: p,
      recipes: data.recipes,
      ingredients: data.ingredients,
      seed: 4,
    );
    expect(plan.days.length, 7);
    for (final d in plan.days) {
      expect(d.meals.length, 4);
    }
    expect(plan.avoidedButPresent(p.disliked), isEmpty);
  });

  test('allergens remain absolute even when avoidance is relaxed', () {
    final p = Profile(
      members: profileAvoiding(const {}).members,
      diet: DietType.veg,
      allergens: {'peanuts', 'milk', 'curd'},
      disliked: {'salt'}, // forces the relax path
    );
    final plan = generateBalancedWeek(
      profile: p,
      recipes: data.recipes,
      ingredients: data.ingredients,
      seed: 5,
    );
    final used = plan.ingredientTotals().keys.toSet();
    expect(used.intersection(p.allergens), isEmpty);
  });

  test('an unavoidable ingredient is reported rather than hidden', () {
    // Salt is in every savoury recipe, so honouring it is impossible.
    final p = profileAvoiding({'salt'});
    final plan = generateBalancedWeek(
      profile: p,
      recipes: data.recipes,
      ingredients: data.ingredients,
      seed: 6,
    );
    expect(plan.avoidedButPresent(p.disliked), contains('salt'),
        reason: 'the app must admit when it could not honour an avoidance');
  });
}
