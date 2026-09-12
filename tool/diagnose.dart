// ignore_for_file: avoid_print
/// Diagnostic: why is a given profile short on a nutrient?
library;

import 'dart:io';

import 'package:healthbuddy/data/food_data.dart';
import 'package:healthbuddy/engine/planner.dart';
import 'package:healthbuddy/engine/targets.dart';
import 'package:healthbuddy/models/profile.dart';

void main() {
  final data = FoodData.parse(
    ingredientsJson: File('assets/seed/ingredients.json').readAsStringSync(),
    recipesJson: File('assets/seed/recipes.json').readAsStringSync(),
  );

  final profile = Profile(
    members: [
      const HouseholdMember(
        id: 'a', name: 'a', age: 30, sex: Sex.male,
        weightKg: 70, heightCm: 175,
        activity: ActivityLevel.sedentary, goal: Goal.lose, isPrimary: true,
      ),
    ],
    diet: DietType.veg,
  );

  final t = householdDailyTargets(profile);
  print('Daily target: ${t.kcal.toStringAsFixed(0)} kcal, '
      '${t.protein.toStringAsFixed(1)}g protein');
  print('Protein density required: '
      '${(t.protein / t.kcal * 1000).toStringAsFixed(1)} g per 1000 kcal');
  print('Portions/day: ${householdPortions(profile).toStringAsFixed(2)}');
  print('');

  // Rank vegetarian recipes by protein density.
  print('Vegetarian recipes by protein density (g protein per 1000 kcal):');
  print('${'recipe'.padRight(34)}${'role'.padRight(10)}'
      '${'kcal/srv'.padLeft(9)}${'P/srv'.padLeft(8)}${'P/1000kcal'.padLeft(12)}');
  final rows = <(String, String, double, double, double)>[];
  for (final r in data.recipes) {
    if (!DietType.veg.admits(r.diet)) continue;
    final p = r.perServing(data.ingredients);
    if (p.kcal <= 0) continue;
    rows.add((r.name, r.role.name, p.kcal, p.protein, p.protein / p.kcal * 1000));
  }
  rows.sort((a, b) => b.$5.compareTo(a.$5));
  for (final r in rows) {
    print('${r.$1.padRight(34)}${r.$2.padRight(10)}'
        '${r.$3.toStringAsFixed(0).padLeft(9)}'
        '${r.$4.toStringAsFixed(1).padLeft(8)}'
        '${r.$5.toStringAsFixed(1).padLeft(12)}');
  }

  print('');
  final plan = generateBalancedWeek(
    profile: profile, recipes: data.recipes,
    ingredients: data.ingredients, seed: 11,
  );
  final got = plan.nutrients(data.ingredients);
  final want = householdWeeklyTargets(profile);
  print('WEEK: ${got.kcal.toStringAsFixed(0)}/${want.kcal.toStringAsFixed(0)} kcal, '
      'protein ${got.protein.toStringAsFixed(0)}/${want.protein.toStringAsFixed(0)}g '
      '(${((got.protein - want.protein) / want.protein * 100).toStringAsFixed(1)}%)');
  print('');
  for (final d in plan.days.take(3)) {
    print(d.dayName);
    for (final m in d.meals) {
      final mn = m.nutrients(data.ingredients);
      print('  ${m.type.label.padRight(10)}'
          '${m.components.map((c) => '${c.recipe.name} ${c.portionLabel()}').join(' + ').padRight(52)}'
          '${mn.kcal.toStringAsFixed(0).padLeft(5)}kcal'
          '${mn.protein.toStringAsFixed(1).padLeft(7)}g P');
    }
  }
}
