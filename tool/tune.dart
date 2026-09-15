// ignore_for_file: avoid_print
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
  final cases = <String, Profile>{
    'veg couple (gain+maintain)': Profile(members: [
      const HouseholdMember(id:'a',name:'a',age:28,sex:Sex.male,weightKg:72,heightCm:175,
        activity:ActivityLevel.moderate,goal:Goal.gain,isPrimary:true),
      const HouseholdMember(id:'b',name:'b',age:27,sex:Sex.female,weightKg:58,heightCm:161,
        activity:ActivityLevel.light,goal:Goal.maintain),
    ], diet: DietType.veg, disliked: {'baingan','bhindi','lauki'}),
    'veg single maintain': Profile(members: [
      const HouseholdMember(id:'a',name:'a',age:30,sex:Sex.male,weightKg:70,heightCm:175,
        activity:ActivityLevel.moderate,goal:Goal.maintain,isPrimary:true),
    ], diet: DietType.veg),
    'veg loss': Profile(members: [
      const HouseholdMember(id:'a',name:'a',age:30,sex:Sex.male,weightKg:70,heightCm:175,
        activity:ActivityLevel.sedentary,goal:Goal.lose,isPrimary:true),
    ], diet: DietType.veg),
    'nonveg family4': Profile(members: [
      const HouseholdMember(id:'a',name:'a',age:35,sex:Sex.male,weightKg:75,heightCm:175,
        activity:ActivityLevel.moderate,goal:Goal.maintain,isPrimary:true),
      const HouseholdMember(id:'b',name:'b',age:33,sex:Sex.female,weightKg:60,heightCm:160,
        activity:ActivityLevel.light,goal:Goal.maintain),
      HouseholdMember.reference(id:'c',name:'c',age:12,sex:Sex.male),
      HouseholdMember.reference(id:'d',name:'d',age:8,sex:Sex.female),
    ], diet: DietType.nonveg),
  };

  print('${"case".padRight(30)}${"protein".padLeft(9)}${"fibre".padLeft(9)}${"kcal".padLeft(8)}${"iron".padLeft(8)}${"Ca".padLeft(8)}');
  cases.forEach((label, p) {
    final need = householdWeeklyTargets(p);
    var pr = 0.0, fi = 0.0, kc = 0.0, ir = 0.0, ca = 0.0;
    const seeds = [1, 7, 13, 21];
    for (final s in seeds) {
      final plan = generateBalancedWeek(
        profile: p, recipes: data.recipes, ingredients: data.ingredients, seed: s);
      final g = plan.nutrients(data.ingredients);
      pr += g.protein/need.protein; fi += g.fibre/need.fibre;
      kc += g.kcal/need.kcal; ir += g.iron/need.iron; ca += g.calcium/need.calcium;
    }
    final n = seeds.length;
    String f(double v) => '${(v/n*100).round()}%';
    print('${label.padRight(30)}${f(pr).padLeft(9)}${f(fi).padLeft(9)}${f(kc).padLeft(8)}${f(ir).padLeft(8)}${f(ca).padLeft(8)}');
  });
}
