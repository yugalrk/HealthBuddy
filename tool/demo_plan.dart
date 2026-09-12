// ignore_for_file: avoid_print

/// Prints a sample week and shopping list to the terminal.
///
/// Pure Dart — no Flutter bindings, no device needed:
///   dart run tool/demo_plan.dart [seed]
library;

import 'dart:io';

import 'package:healthbuddy/data/food_data.dart';
import 'package:healthbuddy/engine/planner.dart';
import 'package:healthbuddy/engine/shopping_list.dart';
import 'package:healthbuddy/engine/targets.dart';
import 'package:healthbuddy/models/food.dart';
import 'package:healthbuddy/models/profile.dart';

String pad(String s, int n) => s.length >= n ? s.substring(0, n) : s.padRight(n);

void main(List<String> args) {
  final seed = args.isEmpty ? 3 : int.parse(args.first);

  final data = FoodData.parse(
    ingredientsJson: File('lib/data/seed/ingredients.json').readAsStringSync(),
    recipesJson: File('lib/data/seed/recipes.json').readAsStringSync(),
  );

  final issues = data.validate();
  if (issues.isNotEmpty) {
    stderr.writeln('Seed data problems:\n${issues.join('\n')}');
    exitCode = 1;
    return;
  }

  // A family of four: two working adults, a teenager and a younger child.
  final profile = Profile(
    members: [
      const HouseholdMember(
        id: 'p1',
        name: 'Yugal',
        age: 28,
        sex: Sex.male,
        weightKg: 72,
        heightCm: 175,
        activity: ActivityLevel.moderate,
        goal: Goal.gain,
        isPrimary: true,
      ),
      const HouseholdMember(
        id: 'p2',
        name: 'Partner',
        age: 27,
        sex: Sex.female,
        weightKg: 58,
        heightCm: 161,
        activity: ActivityLevel.light,
        goal: Goal.maintain,
      ),
      HouseholdMember.reference(
          id: 'p3', name: 'Teen', age: 15, sex: Sex.male),
      HouseholdMember.reference(
          id: 'p4', name: 'Child', age: 8, sex: Sex.female),
    ],
    diet: DietType.veg,
    disliked: {'baingan'},
    liked: {'paneer'},
    pantry: {'salt', 'haldi', 'oil'},
  );

  print('=' * 74);
  print('HOUSEHOLD');
  print('=' * 74);
  for (final mt in memberBreakdown(profile)) {
    final m = mt.member;
    print('${pad(m.name, 10)} ${pad('${m.age}y ${m.sex.name}', 12)} '
        '${pad('${m.weightKg.toStringAsFixed(0)}kg', 7)} '
        '${pad(m.goal.label, 14)} '
        '${mt.targets.kcal.toStringAsFixed(0).padLeft(5)} kcal  '
        '${mt.targets.protein.toStringAsFixed(0).padLeft(3)}g protein '
        '(${mt.proteinGPerKg.toStringAsFixed(2)} g/kg)');
  }
  final dayT = householdDailyTargets(profile);
  print('-' * 74);
  print('Household/day: ${dayT.kcal.toStringAsFixed(0)} kcal, '
      '${dayT.protein.toStringAsFixed(0)}g protein, '
      '${dayT.fat.toStringAsFixed(0)}g fat, '
      '${dayT.carb.toStringAsFixed(0)}g carb, '
      '${dayT.fibre.toStringAsFixed(0)}g fibre');
  print('Standard portions cooked per day: '
      '${householdPortions(profile).toStringAsFixed(2)}');

  final plan = generateBalancedWeek(
    profile: profile,
    recipes: data.recipes,
    ingredients: data.ingredients,
    seed: seed,
  );

  print('');
  print('=' * 74);
  print('WEEK PLAN (seed $seed)');
  print('=' * 74);
  for (final d in plan.days) {
    final n = d.nutrients(data.ingredients);
    print('\n${d.dayName}${d.isWeekend ? '  (weekend)' : ''}   '
        '${n.kcal.toStringAsFixed(0)} kcal · ${n.protein.toStringAsFixed(0)}g protein');
    for (final m in d.meals) {
      final mn = m.nutrients(data.ingredients);
      final parts = m.components
          .map((c) => '${c.recipe.name} ${c.portionLabel()}')
          .join(' + ');
      print('  ${pad(m.type.label, 10)} ${pad(parts, 46)} '
          '${mn.kcal.toStringAsFixed(0).padLeft(4)}kcal '
          '${mn.protein.toStringAsFixed(0).padLeft(3)}g P');
    }
  }

  final got = plan.nutrients(data.ingredients);
  final want = householdWeeklyTargets(profile);
  print('');
  print('=' * 74);
  print('WEEKLY BALANCE  (planned vs target)');
  print('=' * 74);
  void row(String label, double g, double w, String unit) {
    final pct = (g - w) / w * 100;
    final sign = pct >= 0 ? '+' : '';
    print('  ${pad(label, 10)} ${g.toStringAsFixed(0).padLeft(7)} $unit  '
        'target ${w.toStringAsFixed(0).padLeft(7)} $unit   '
        '$sign${pct.toStringAsFixed(1)}%');
  }

  row('Energy', got.kcal, want.kcal, 'kcal');
  row('Protein', got.protein, want.protein, 'g');
  row('Fat', got.fat, want.fat, 'g');
  row('Carbs', got.carb, want.carb, 'g');
  row('Fibre', got.fibre, want.fibre, 'g');
  row('Iron', got.iron, want.iron, 'mg');
  row('Calcium', got.calcium, want.calcium, 'mg');

  final list = buildShoppingList(
    plan: plan,
    ingredients: data.ingredients,
    profile: profile,
  );

  print('');
  print('=' * 74);
  print('SHOPPING LIST FOR THE WEEK  (${list.itemCount} items)');
  print('=' * 74);
  for (final aisle in list.orderedAisles) {
    print('\n${aisle.label}');
    for (final it in list.toBuy[aisle]!) {
      final over = it.overageLabel;
      print('  [ ] ${pad(it.ingredient.name, 30)} ${pad(it.quantityLabel, 10)}'
          '${over == null ? '' : '   ($over)'}');
    }
  }
  if (list.pantryCheck.isNotEmpty) {
    print('\nCheck you already have');
    print('  ${list.pantryCheck.map((i) => i.ingredient.name).join(', ')}');
  }
  if (list.excludedOwned.isNotEmpty) {
    print('\nSkipped (you said you have these)');
    print('  ${list.excludedOwned.map((i) => i.name).join(', ')}');
  }

  final byId = {for (final r in data.recipes) r.id: r};
  final distinctMains = plan
      .recipeFrequency()
      .keys
      .where((id) => byId[id]?.role == RecipeRole.main)
      .length;
  final distinctSabzis = plan
      .recipeFrequency()
      .keys
      .where((id) => byId[id]?.role == RecipeRole.sabzi)
      .length;
  print('\nVariety: $distinctMains distinct protein mains and '
      '$distinctSabzis sabzis across the week.');
}
