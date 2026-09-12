import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbuddy/data/food_data.dart';
import 'package:healthbuddy/engine/planner.dart';
import 'package:healthbuddy/engine/shopping_list.dart';
import 'package:healthbuddy/engine/targets.dart';
import 'package:healthbuddy/models/food.dart';
import 'package:healthbuddy/models/plan.dart';
import 'package:healthbuddy/models/profile.dart';

/// Loads the real bundled seed data straight from disk — no Flutter bindings,
/// so these run headlessly.
FoodData loadSeed() => FoodData.parse(
      ingredientsJson:
          File('lib/data/seed/ingredients.json').readAsStringSync(),
      recipesJson: File('lib/data/seed/recipes.json').readAsStringSync(),
    );

HouseholdMember adult({
  String id = 'a',
  Sex sex = Sex.male,
  double weightKg = 70,
  double heightCm = 175,
  int age = 30,
  Goal goal = Goal.maintain,
  ActivityLevel activity = ActivityLevel.moderate,
  bool primary = true,
}) =>
    HouseholdMember(
      id: id,
      name: id,
      age: age,
      sex: sex,
      weightKg: weightKg,
      heightCm: heightCm,
      activity: activity,
      goal: goal,
      isPrimary: primary,
    );

void main() {
  late FoodData data;

  setUpAll(() => data = loadSeed());

  group('seed data integrity', () {
    test('parses and passes referential validation', () {
      final issues = data.validate();
      expect(issues, isEmpty, reason: issues.join('\n'));
    });

    test('has enough recipes in every slot to build a varied week', () {
      for (final slot in MealType.values) {
        final n = data.recipes.where((r) => r.slots.contains(slot)).length;
        expect(n, greaterThanOrEqualTo(5), reason: 'slot $slot has only $n');
      }
    });

    test('a pure vegetarian still has a workable recipe set', () {
      final veg =
          data.recipes.where((r) => DietType.veg.admits(r.diet)).toList();
      expect(veg.where((r) => r.role == RecipeRole.main).length,
          greaterThanOrEqualTo(10));
      expect(veg.where((r) => r.slots.contains(MealType.breakfast)).length,
          greaterThanOrEqualTo(5));
      expect(veg.where((r) => r.role == RecipeRole.staple).length,
          greaterThanOrEqualTo(3));
    });

    test('every unverified estimate is declared, not hidden', () {
      // This test documents the outstanding review work rather than failing the
      // build; see docs/NUTRITION_SOURCES.md.
      expect(data.unverified.length, lessThanOrEqualTo(10),
          reason: 'unverified: ${data.unverified.map((i) => i.id).join(", ")}');
    });
  });

  group('weekly plan', () {
    Profile profileFor(DietType diet, List<HouseholdMember> members) =>
        Profile(members: members, diet: diet);

    test('produces seven days with every meal filled', () {
      final p = profileFor(DietType.veg, [adult()]);
      final plan = generateBalancedWeek(
        profile: p,
        recipes: data.recipes,
        ingredients: data.ingredients,
        seed: 1,
      );
      expect(plan.days.length, 7);
      for (final d in plan.days) {
        expect(d.meals.length, 4, reason: 'day ${d.dayName}');
        for (final m in d.meals) {
          expect(m.components, isNotEmpty);
        }
      }
    });

    test('lunch and dinner are built from a main plus a staple', () {
      final p = profileFor(DietType.veg, [adult()]);
      final plan = generateBalancedWeek(
        profile: p,
        recipes: data.recipes,
        ingredients: data.ingredients,
        seed: 2,
      );
      for (final d in plan.days) {
        for (final t in [MealType.lunch, MealType.dinner]) {
          final meal = d.mealOf(t)!;
          final roles = meal.components.map((c) => c.recipe.role).toSet();
          expect(roles, contains(RecipeRole.main),
              reason: '${d.dayName} ${t.name}');
        }
      }
    });

    test('is deterministic for a given seed', () {
      final p = profileFor(DietType.veg, [adult()]);
      List<String> run() => generateBalancedWeek(
            profile: p,
            recipes: data.recipes,
            ingredients: data.ingredients,
            seed: 7,
          )
              .days
              .expand((d) => d.meals.expand((m) => m.components))
              .map((c) => '${c.recipe.id}@${c.servings}')
              .toList();
      expect(run(), equals(run()));
    });

    test('different seeds give different weeks', () {
      final p = profileFor(DietType.veg, [adult()]);
      List<String> run(int s) => generateBalancedWeek(
            profile: p,
            recipes: data.recipes,
            ingredients: data.ingredients,
            seed: s,
          )
              .days
              .expand((d) => d.meals.map((m) => m.title))
              .toList();
      expect(run(1), isNot(equals(run(42))));
    });

    test('meets weekly energy and protein targets across many household shapes',
        () {
      final cases = <String, Profile>{
        'single veg male': profileFor(DietType.veg, [adult()]),
        'single veg female': profileFor(DietType.veg, [
          adult(sex: Sex.female, weightKg: 55, heightCm: 160),
        ]),
        'couple nonveg': profileFor(DietType.nonveg, [
          adult(),
          adult(id: 'b', sex: Sex.female, weightKg: 58, heightCm: 162, primary: false),
        ]),
        'family of four egg': profileFor(DietType.egg, [
          adult(),
          adult(id: 'b', sex: Sex.female, weightKg: 58, heightCm: 162, primary: false),
          HouseholdMember.reference(
              id: 'c', name: 'child', age: 9, sex: Sex.female),
          HouseholdMember.reference(
              id: 'd', name: 'teen', age: 15, sex: Sex.male),
        ]),
        'veg muscle gain': profileFor(DietType.veg, [
          adult(goal: Goal.gain, activity: ActivityLevel.active),
        ]),
        'veg weight loss': profileFor(DietType.veg, [
          adult(goal: Goal.lose, activity: ActivityLevel.sedentary),
        ]),
        'household of six': profileFor(DietType.veg, [
          adult(),
          adult(id: 'b', sex: Sex.female, weightKg: 58, heightCm: 162, primary: false),
          HouseholdMember.reference(id: 'c', name: 'c', age: 12, sex: Sex.male),
          HouseholdMember.reference(id: 'd', name: 'd', age: 8, sex: Sex.female),
          HouseholdMember.reference(id: 'e', name: 'e', age: 65, sex: Sex.male),
          HouseholdMember.reference(id: 'f', name: 'f', age: 62, sex: Sex.female),
        ]),
      };

      cases.forEach((label, p) {
        final plan = generateBalancedWeek(
          profile: p,
          recipes: data.recipes,
          ingredients: data.ingredients,
          seed: 11,
        );
        final got = plan.nutrients(data.ingredients);
        final want = householdWeeklyTargets(p);

        final kcalErr = (got.kcal - want.kcal).abs() / want.kcal;
        final protErr = (got.protein - want.protein) / want.protein;

        expect(kcalErr, lessThan(0.12),
            reason: '$label energy off by ${(kcalErr * 100).toStringAsFixed(1)}%'
                ' (got ${got.kcal.toStringAsFixed(0)}, want ${want.kcal.toStringAsFixed(0)})');
        // Protein may overshoot freely; it must not fall meaningfully short.
        expect(protErr, greaterThan(-0.08),
            reason: '$label protein short by '
                '${(-protErr * 100).toStringAsFixed(1)}%'
                ' (got ${got.protein.toStringAsFixed(0)}g, want ${want.protein.toStringAsFixed(0)}g)');
      });
    });

    test('scales food quantities with household size', () {
      final one = profileFor(DietType.veg, [adult()]);
      final four = profileFor(DietType.veg, [
        adult(),
        adult(id: 'b', sex: Sex.female, weightKg: 58, heightCm: 162, primary: false),
        HouseholdMember.reference(id: 'c', name: 'c', age: 12, sex: Sex.male),
        HouseholdMember.reference(id: 'd', name: 'd', age: 9, sex: Sex.female),
      ]);

      double totalGrams(Profile p) {
        final plan = generateBalancedWeek(
          profile: p,
          recipes: data.recipes,
          ingredients: data.ingredients,
          seed: 5,
        );
        return plan.ingredientTotals().values.fold(0.0, (a, b) => a + b);
      }

      final g1 = totalGrams(one);
      final g4 = totalGrams(four);
      expect(g4, greaterThan(g1 * 2.0),
          reason: 'four people should need substantially more food than one');
    });

    test('respects diet restrictions absolutely', () {
      final p = profileFor(DietType.veg, [adult()]);
      final plan = generateBalancedWeek(
        profile: p,
        recipes: data.recipes,
        ingredients: data.ingredients,
        seed: 3,
      );
      for (final d in plan.days) {
        for (final m in d.meals) {
          for (final c in m.components) {
            expect(c.recipe.diet, DietType.veg,
                reason: '${c.recipe.name} is not vegetarian');
            for (final id in c.recipe.ingredientIds) {
              expect(data.ingredients[id]!.diet, DietType.veg);
            }
          }
        }
      }
    });

    test('never plans an allergen', () {
      final p = Profile(
        members: [adult()],
        diet: DietType.veg,
        allergens: {'peanuts', 'milk', 'curd', 'paneer'},
      );
      final plan = generateBalancedWeek(
        profile: p,
        recipes: data.recipes,
        ingredients: data.ingredients,
        seed: 4,
      );
      final used = plan.ingredientTotals().keys.toSet();
      for (final a in p.allergens) {
        expect(used, isNot(contains(a)), reason: '$a was planned despite allergy');
      }
    });

    test('avoids serving the same dish on consecutive days', () {
      final p = profileFor(DietType.veg, [adult()]);
      final plan = generateBalancedWeek(
        profile: p,
        recipes: data.recipes,
        ingredients: data.ingredients,
        seed: 9,
      );
      for (var i = 1; i < plan.days.length; i++) {
        for (final t in [MealType.lunch, MealType.dinner]) {
          final prev = plan.days[i - 1].mealOf(t);
          final cur = plan.days[i].mealOf(t);
          if (prev == null || cur == null) continue;
          String? mainOf(PlannedMeal m) {
            for (final c in m.components) {
              if (c.recipe.role == RecipeRole.main) return c.recipe.id;
            }
            return null;
          }

          final a = mainOf(prev);
          final b = mainOf(cur);
          if (a != null && b != null) {
            expect(b, isNot(equals(a)),
                reason: 'same main two days running at ${t.name}');
          }
        }
      }
    });

    test('uses a reasonable variety of dishes over the week', () {
      final p = profileFor(DietType.veg, [adult()]);
      final plan = generateBalancedWeek(
        profile: p,
        recipes: data.recipes,
        ingredients: data.ingredients,
        seed: 13,
      );
      final distinctMains = plan.days
          .expand((d) => d.meals)
          .expand((m) => m.components)
          .where((c) => c.recipe.role == RecipeRole.main)
          .map((c) => c.recipe.id)
          .toSet();
      expect(distinctMains.length, greaterThanOrEqualTo(6),
          reason: 'only ${distinctMains.length} distinct mains in a week');
    });
  });

  group('shopping list', () {
    test('covers every planned ingredient and rounds up to pack sizes', () {
      final p = Profile(members: [adult()], diet: DietType.veg);
      final plan = generateBalancedWeek(
        profile: p,
        recipes: data.recipes,
        ingredients: data.ingredients,
        seed: 21,
      );
      final list = buildShoppingList(
        plan: plan,
        ingredients: data.ingredients,
        profile: p,
      );

      final planned = plan.ingredientTotals();
      final listed = <String, ShoppingItem>{
        for (final items in list.toBuy.values)
          for (final i in items) i.ingredient.id: i,
        for (final i in list.pantryCheck) i.ingredient.id: i,
      };

      for (final id in planned.keys) {
        expect(listed.containsKey(id), isTrue,
            reason: '$id was planned but is missing from the shopping list');
        final item = listed[id]!;
        expect(item.buyQty, greaterThanOrEqualTo(item.neededQty),
            reason: 'buying less $id than the recipes need');
        expect(item.buyQty, closeTo(item.packs * item.ingredient.packSize, 1e-9));
      }
    });

    test('keeps weekly spices out of the buy list', () {
      final p = Profile(members: [adult()], diet: DietType.veg);
      final plan = generateBalancedWeek(
        profile: p,
        recipes: data.recipes,
        ingredients: data.ingredients,
        seed: 22,
      );
      final list = buildShoppingList(
        plan: plan,
        ingredients: data.ingredients,
        profile: p,
      );
      final buyIds = {
        for (final items in list.toBuy.values) for (final i in items) i.ingredient.id
      };
      expect(buyIds, isNot(contains('haldi')));
      expect(buyIds, isNot(contains('salt')));
      expect(list.pantryCheck.map((i) => i.ingredient.id), contains('haldi'));
    });

    test('drops items the household already owns', () {
      final plan = generateBalancedWeek(
        profile: Profile(members: [adult()], diet: DietType.veg),
        recipes: data.recipes,
        ingredients: data.ingredients,
        seed: 23,
      );
      final owned = plan.ingredientTotals().keys.take(3).toSet();
      final p = Profile(
        members: [adult()],
        diet: DietType.veg,
        pantry: owned,
      );
      final list =
          buildShoppingList(plan: plan, ingredients: data.ingredients, profile: p);
      final listedIds = {
        for (final items in list.toBuy.values) for (final i in items) i.ingredient.id,
        for (final i in list.pantryCheck) i.ingredient.id,
      };
      for (final o in owned) {
        expect(listedIds, isNot(contains(o)));
      }
      expect(list.excludedOwned.map((i) => i.id).toSet(), equals(owned));
    });

    test('a larger household buys more', () {
      double totalPacks(Profile p) {
        final plan = generateBalancedWeek(
          profile: p,
          recipes: data.recipes,
          ingredients: data.ingredients,
          seed: 24,
        );
        final list = buildShoppingList(
            plan: plan, ingredients: data.ingredients, profile: p);
        return list.toBuy.values
            .expand((e) => e)
            .fold(0.0, (a, i) => a + i.buyQty);
      }

      final one = Profile(members: [adult()], diet: DietType.veg);
      final five = Profile(members: [
        adult(),
        adult(id: 'b', sex: Sex.female, weightKg: 58, heightCm: 162, primary: false),
        HouseholdMember.reference(id: 'c', name: 'c', age: 14, sex: Sex.male),
        HouseholdMember.reference(id: 'd', name: 'd', age: 11, sex: Sex.female),
        HouseholdMember.reference(id: 'e', name: 'e', age: 40, sex: Sex.male),
      ], diet: DietType.veg);

      expect(totalPacks(five), greaterThan(totalPacks(one)));
    });

    test('share text lists aisles and items', () {
      final p = Profile(members: [adult()], diet: DietType.veg);
      final plan = generateBalancedWeek(
        profile: p,
        recipes: data.recipes,
        ingredients: data.ingredients,
        seed: 25,
      );
      final text = buildShoppingList(
              plan: plan, ingredients: data.ingredients, profile: p)
          .toShareText();
      expect(text, contains('Shopping list'));
      expect(text, contains(Aisle.pulses.label));
    });
  });
}
