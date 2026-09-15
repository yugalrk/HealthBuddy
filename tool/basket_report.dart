// ignore_for_file: avoid_print
/// Shows what a week's basket provides, grouped by nutritional role.
library;

import 'dart:io';
import 'package:healthbuddy/data/food_data.dart';
import 'package:healthbuddy/engine/planner.dart';
import 'package:healthbuddy/engine/shopping_list.dart';
import 'package:healthbuddy/engine/targets.dart';
import 'package:healthbuddy/models/food.dart';
import 'package:healthbuddy/models/profile.dart';

void main() {
  final data = FoodData.parse(
    ingredientsJson: File('assets/seed/ingredients.json').readAsStringSync(),
    recipesJson: File('assets/seed/recipes.json').readAsStringSync(),
  );
  final p = Profile(
    members: [
      const HouseholdMember(id:'a',name:'You',age:28,sex:Sex.male,weightKg:72,
        heightCm:175,activity:ActivityLevel.moderate,goal:Goal.gain,isPrimary:true),
      const HouseholdMember(id:'b',name:'Partner',age:27,sex:Sex.female,weightKg:58,
        heightCm:161,activity:ActivityLevel.light,goal:Goal.maintain),
    ],
    diet: DietType.veg,
    disliked: {'baingan','bhindi','lauki'},
  );

  print('RECOMMENDED DAILY INTAKE');
  final daily = householdDailyTargets(p);
  for (final g in nutrientGuides) {
    print('  ${g.label.padRight(14)}${g.read(daily).round().toString().padLeft(6)} ${g.unit}');
  }

  final plan = generateBalancedWeek(
      profile: p, recipes: data.recipes, ingredients: data.ingredients, seed: 3);
  final list = buildShoppingList(
      plan: plan, ingredients: data.ingredients, profile: p);

  print('');
  print('AVOIDED: ${p.disliked.join(", ")}');
  print('  still present: ${plan.avoidedButPresent(p.disliked).isEmpty ? "none" : plan.avoidedButPresent(p.disliked).join(", ")}');

  print('');
  print('BASKET COVERAGE vs weekly need');
  final need = householdWeeklyTargets(p);
  final cov = list.coverageAgainst(need);
  for (final (label, got, want, unit, ratio) in [
    ('Protein', list.provides.protein, need.protein, 'g', cov.protein),
    ('Energy', list.provides.kcal, need.kcal, 'kcal', cov.kcal),
    ('Fibre', list.provides.fibre, need.fibre, 'g', cov.fibre),
    ('Iron', list.provides.iron, need.iron, 'mg', cov.iron),
    ('Calcium', list.provides.calcium, need.calcium, 'mg', cov.calcium),
  ]) {
    print('  ${label.padRight(9)}${got.round().toString().padLeft(6)} / ${want.round().toString().padLeft(6)} $unit  ${(ratio*100).round()}%');
  }
  print('  cereal protein share: ${(list.cerealProteinShare*100).round()}%');

  print('');
  print('BASKET BY NUTRITIONAL ROLE');
  final grouped = list.byNutrientRole;
  for (final role in list.orderedRoles) {
    final items = grouped[role]!;
    var n = const Nutrients();
    for (final i in items) { n += i.contribution; }
    print('  ${role.label} — ${n.protein.round()}g protein, ${n.kcal.round()} kcal, ${n.calcium.round()}mg Ca');
    print('    ${items.take(6).map((i) => i.ingredient.name).join(", ")}${items.length>6 ? " ..." : ""}');
  }
}
