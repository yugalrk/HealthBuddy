import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbuddy/data/food_data.dart';
import 'package:healthbuddy/engine/planner.dart';
import 'package:healthbuddy/engine/shopping_list.dart';
import 'package:healthbuddy/engine/targets.dart';
import 'package:healthbuddy/models/food.dart';
import 'package:healthbuddy/models/profile.dart';

FoodData loadSeed() => FoodData.parse(
      ingredientsJson: File('assets/seed/ingredients.json').readAsStringSync(),
      recipesJson: File('assets/seed/recipes.json').readAsStringSync(),
    );

Profile household(int extra) => Profile(
      members: [
        const HouseholdMember(
          id: 'a',
          name: 'a',
          age: 32,
          sex: Sex.male,
          weightKg: 72,
          heightCm: 176,
          activity: ActivityLevel.moderate,
          goal: Goal.maintain,
          isPrimary: true,
        ),
        for (var i = 0; i < extra; i++)
          HouseholdMember.reference(
              id: 'm$i', name: 'm$i', age: 30 + i, sex: Sex.female),
      ],
      diet: DietType.veg,
    );

void main() {
  late FoodData data;
  setUpAll(() => data = loadSeed());

  ShoppingList listFor(Profile p, {int seed = 12}) {
    final plan = generateBalancedWeek(
      profile: p,
      recipes: data.recipes,
      ingredients: data.ingredients,
      seed: seed,
    );
    return buildShoppingList(
        plan: plan, ingredients: data.ingredients, profile: p);
  }

  group('ingredient nutritional roles', () {
    test('paneer and tofu count as protein foods, milk and curd as dairy', () {
      expect(data.ingredients['paneer']!.role, NutrientRole.protein);
      expect(data.ingredients['tofu']!.role, NutrientRole.protein);
      expect(data.ingredients['milk']!.role, NutrientRole.dairy);
      expect(data.ingredients['curd']!.role, NutrientRole.dairy);
    });

    test('dals are protein, grains are grains, spices are flavour', () {
      expect(data.ingredients['toor_dal']!.role, NutrientRole.protein);
      expect(data.ingredients['soya_chunks']!.role, NutrientRole.protein);
      expect(data.ingredients['atta']!.role, NutrientRole.grain);
      expect(data.ingredients['rice_raw']!.role, NutrientRole.grain);
      expect(data.ingredients['haldi']!.role, NutrientRole.flavour);
      expect(data.ingredients['oil']!.role, NutrientRole.fat);
    });

    test('every ingredient classifies without throwing', () {
      for (final i in data.ingredients.values) {
        expect(() => i.role, returnsNormally, reason: i.id);
      }
    });
  });

  group('basket coverage', () {
    test('the basket supplies the week it was built for', () {
      for (final extra in [0, 1, 3]) {
        final p = household(extra);
        final list = listFor(p);
        final cover = list.coverageAgainst(householdWeeklyTargets(p));

        // The basket is what the cooking consumes, so it should land close to
        // the plan's own totals rather than drifting from them.
        expect(cover.protein, greaterThan(0.9),
            reason: 'household of ${extra + 1}: protein coverage '
                '${(cover.protein * 100).toStringAsFixed(0)}%');
        expect(cover.kcal, greaterThan(0.9),
            reason: 'household of ${extra + 1}: energy coverage '
                '${(cover.kcal * 100).toStringAsFixed(0)}%');
      }
    });

    test('a bigger household needs a bigger basket', () {
      final small = listFor(household(0)).provides;
      final large = listFor(household(3)).provides;
      expect(large.protein, greaterThan(small.protein * 1.8));
      expect(large.kcal, greaterThan(small.kcal * 1.8));
    });

    test('every item appears in exactly one nutritional group', () {
      final list = listFor(household(1));
      final grouped = list.byNutrientRole;
      final totalGrouped =
          grouped.values.fold<int>(0, (a, b) => a + b.length);
      expect(totalGrouped, list.allItems.length);
      expect(list.orderedRoles, isNotEmpty);
    });

    test('protein and grains dominate protein supply, and grains can lead', () {
      final list = listFor(household(1));
      final grouped = list.byNutrientRole;
      double proteinOf(NutrientRole r) => (grouped[r] ?? [])
          .fold(0.0, (a, i) => a + i.contribution.protein);

      final fromProteinFoods = proteinOf(NutrientRole.protein);
      final fromGrains = proteinOf(NutrientRole.grain);
      final total = list.provides.protein;

      // Grains legitimately out-supply the dals and paneer in an Indian
      // vegetarian week: atta is ~12% protein and is eaten in quantity. That
      // is exactly why ICMR-NIN raises the requirement for cereal-based diets
      // — a large share of the protein is lower-quality cereal protein.
      expect(fromProteinFoods + fromGrains, greaterThan(total * 0.6),
          reason: 'protein should come mainly from dals/paneer and grains');

      // No other group should rival either of them.
      for (final r in NutrientRole.values) {
        if (r == NutrientRole.protein || r == NutrientRole.grain) continue;
        expect(proteinOf(r), lessThan(fromProteinFoods),
            reason: '${r.label} out-supplied the protein foods');
      }
    });

    test('cereal protein share is reported so the diet quality is visible', () {
      final list = listFor(household(1));
      final share = list.cerealProteinShare;
      expect(share, greaterThan(0.2));
      expect(share, lessThan(0.8));
    });
  });

  group('recommended intake reporting', () {
    test('a guide exists for every nutrient the app reports', () {
      final labels = nutrientGuides.map((g) => g.label).toSet();
      expect(labels, containsAll(<String>[
        'Energy',
        'Protein',
        'Fat',
        'Carbohydrate',
        'Fibre',
        'Iron',
        'Calcium',
      ]));
    });

    test('each guide reads a sensible value and explains itself', () {
      final t = targetsForMember(household(0).primary, DietType.veg);
      for (final g in nutrientGuides) {
        expect(g.read(t), greaterThan(0), reason: g.label);
        expect(g.why, isNotEmpty);
        expect(g.basis, isNotEmpty);
      }
    });

    test('the protein guide cites the vegetarian adjustment', () {
      final protein = nutrientGuides.firstWhere((g) => g.label == 'Protein');
      expect(protein.basis, contains('0.83'));
      expect(protein.basis, contains('1.0 g/kg'));
    });
  });
}
