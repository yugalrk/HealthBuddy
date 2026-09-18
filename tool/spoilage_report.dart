// ignore_for_file: avoid_print

/// How much food a week would waste, and what the shops look like, across
/// household shapes and shopping rhythms.
///
///   dart run tool/spoilage_report.dart
library;

import 'dart:io';

import 'package:healthbuddy/data/food_data.dart';
import 'package:healthbuddy/engine/planner.dart';
import 'package:healthbuddy/engine/stock.dart';
import 'package:healthbuddy/engine/targets.dart';
import 'package:healthbuddy/models/profile.dart';

void main() {
  final data = FoodData.parse(
    ingredientsJson: File('assets/seed/ingredients.json').readAsStringSync(),
    recipesJson: File('assets/seed/recipes.json').readAsStringSync(),
  );

  const adult = HouseholdMember(
    id: 'a',
    name: 'a',
    age: 30,
    sex: Sex.male,
    weightKg: 70,
    heightCm: 175,
    activity: ActivityLevel.moderate,
    goal: Goal.maintain,
    isPrimary: true,
  );
  final households = {
    'single veg': [adult],
    'family of 4': [
      adult,
      adult,
      HouseholdMember.reference(id: 'c', name: 'c', age: 14, sex: Sex.male),
      HouseholdMember.reference(id: 'd', name: 'd', age: 8, sex: Sex.female),
    ],
  };

  for (final h in households.entries) {
    for (final diet in [DietType.veg, DietType.nonveg]) {
      for (final rhythm in ShoppingRhythm.values) {
        final profile =
            Profile(members: h.value, diet: diet, shopping: rhythm);
        var waste = 0.0;
        var topUps = 0;
        var pShort = 0.0;
        final sw = Stopwatch()..start();
        const seeds = 5;
        final wasted = <String, double>{};
        for (var seed = 0; seed < seeds; seed++) {
          final plan = generateBalancedWeek(
            profile: profile,
            recipes: data.recipes,
            ingredients: data.ingredients,
            seed: seed,
          );
          final l = StockLedger.replay(
              plan: plan, ingredients: data.ingredients, profile: profile);
          waste += l.wasteScore;
          topUps += l.purchases.where((p) => p.topUp).length;
          l.wasted.forEach((k, v) => wasted[k] = (wasted[k] ?? 0) + v);
          final got = plan.nutrients(data.ingredients).protein;
          final want = householdWeeklyTargets(profile).protein;
          pShort += (want - got).clamp(0, double.infinity) / want;
        }
        print('${h.key.padRight(12)} ${diet.name.padRight(7)} '
            '${rhythm.name.padRight(9)} waste ${(waste / seeds).toStringAsFixed(2)} packs/wk  '
            'top-ups ${(topUps / seeds).toStringAsFixed(1)}  '
            'protein short ${(pShort / seeds * 100).toStringAsFixed(1)}%  '
            '${sw.elapsedMilliseconds ~/ seeds} ms  '
            '${wasted.entries.map((e) => '${e.key} ${(e.value / seeds).round()}').join(', ')}');
      }
    }
  }
}
