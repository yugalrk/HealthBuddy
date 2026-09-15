import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbuddy/data/food_data.dart';
import 'package:healthbuddy/engine/planner.dart';
import 'package:healthbuddy/models/profile.dart';
import 'package:healthbuddy/ui/plan/plan_screen.dart';

void main() {
  test('meal amounts add up to the week\'s ingredient totals', () {
    final data = FoodData.parse(
      ingredientsJson: File('assets/seed/ingredients.json').readAsStringSync(),
      recipesJson: File('assets/seed/recipes.json').readAsStringSync(),
    );
    final p = Profile(
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
      diet: DietType.veg,
    );
    final plan = generateBalancedWeek(
        profile: p,
        recipes: data.recipes,
        ingredients: data.ingredients,
        seed: 5);

    final summed = <String, double>{};
    for (final d in plan.days) {
      for (final m in d.meals) {
        m.ingredientQuantities().forEach((id, q) {
          summed[id] = (summed[id] ?? 0) + q;
        });
      }
    }
    final totals = plan.ingredientTotals();
    expect(summed.keys.toSet(), totals.keys.toSet());
    for (final id in totals.keys) {
      expect(summed[id], closeTo(totals[id]!, 1e-6));
    }
  });

  test('cook quantities round to measurable amounts', () {
    expect(formatCookQty(247.3, 'g'), '250 g');
    expect(formatCookQty(37.6, 'g'), '40 g');
    expect(formatCookQty(6.4, 'g'), '6 g');
    expect(formatCookQty(0.3, 'g'), '<1 g');
    expect(formatCookQty(1240, 'ml'), '1.2 L');
  });
}
