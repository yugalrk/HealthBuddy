// ignore_for_file: avoid_print
import 'dart:io';
import 'package:healthbuddy/data/food_data.dart';
import 'package:healthbuddy/engine/planner.dart';
import 'package:healthbuddy/models/profile.dart';

void main() {
  final data = FoodData.parse(
    ingredientsJson: File('assets/seed/ingredients.json').readAsStringSync(),
    recipesJson: File('assets/seed/recipes.json').readAsStringSync(),
  );
  final p = Profile(members: [
    const HouseholdMember(id:'a',name:'a',age:30,sex:Sex.male,weightKg:72,heightCm:175,
      activity:ActivityLevel.moderate,goal:Goal.gain,isPrimary:true),
    const HouseholdMember(id:'b',name:'b',age:28,sex:Sex.female,weightKg:58,heightCm:160,
      activity:ActivityLevel.light,goal:Goal.maintain),
  ], diet: DietType.veg);

  // warm up the JIT the way a real second tap would be
  generateBalancedWeek(profile:p,recipes:data.recipes,ingredients:data.ingredients,seed:0);

  final sw = Stopwatch()..start();
  const n = 10;
  for (var i = 0; i < n; i++) {
    generateBalancedWeek(profile:p,recipes:data.recipes,ingredients:data.ingredients,seed:i);
  }
  sw.stop();
  print('avg generateBalancedWeek: ${(sw.elapsedMilliseconds/n).toStringAsFixed(0)} ms');
}
