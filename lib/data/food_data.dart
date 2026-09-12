/// Loading and validating the bundled food database.
///
/// [FoodData.parse] is pure Dart with no Flutter dependency, so the engine
/// tests can load the real seed files directly from disk without a test
/// harness or a device.
library;

import 'dart:convert';

import '../models/food.dart';

class FoodDataIssue {
  const FoodDataIssue(this.recipeId, this.message);
  final String recipeId;
  final String message;

  @override
  String toString() => '$recipeId: $message';
}

class FoodData {
  const FoodData({required this.ingredients, required this.recipes});

  final Map<String, Ingredient> ingredients;
  final List<Recipe> recipes;

  static FoodData parse({
    required String ingredientsJson,
    required String recipesJson,
  }) {
    final ingRoot = json.decode(ingredientsJson) as Map<String, dynamic>;
    final recRoot = json.decode(recipesJson) as Map<String, dynamic>;

    final ingredients = <String, Ingredient>{};
    for (final e in (ingRoot['ingredients'] as List).cast<Map<String, dynamic>>()) {
      final ing = Ingredient.fromJson(e);
      ingredients[ing.id] = ing;
    }

    final recipes = [
      for (final e in (recRoot['recipes'] as List).cast<Map<String, dynamic>>())
        Recipe.fromJson(e)
    ];

    return FoodData(ingredients: ingredients, recipes: recipes);
  }

  /// Referential integrity check. Run in tests and in debug builds — a recipe
  /// pointing at a missing ingredient would silently under-count nutrition,
  /// which is precisely the kind of bug a nutrition app must not ship.
  List<FoodDataIssue> validate() {
    final issues = <FoodDataIssue>[];
    final seenRecipeIds = <String>{};

    for (final r in recipes) {
      if (!seenRecipeIds.add(r.id)) {
        issues.add(FoodDataIssue(r.id, 'duplicate recipe id'));
      }
      if (r.servings <= 0) {
        issues.add(FoodDataIssue(r.id, 'servings must be > 0'));
      }
      if (r.lines.isEmpty) {
        issues.add(FoodDataIssue(r.id, 'no ingredients'));
      }
      if (r.slots.isEmpty) {
        issues.add(FoodDataIssue(r.id, 'no meal slots'));
      }
      for (final l in r.lines) {
        if (!ingredients.containsKey(l.ingredientId)) {
          issues.add(
              FoodDataIssue(r.id, 'unknown ingredient "${l.ingredientId}"'));
        }
        if (l.qty <= 0) {
          issues.add(
              FoodDataIssue(r.id, 'non-positive qty for "${l.ingredientId}"'));
        }
      }
      // A recipe whose declared diet is stricter than its ingredients would let
      // a vegetarian be served egg or meat.
      for (final id in r.ingredientIds) {
        final ing = ingredients[id];
        if (ing == null) continue;
        if (ing.diet.index > r.diet.index) {
          issues.add(FoodDataIssue(
              r.id,
              'declared ${r.diet.name} but contains ${ing.diet.name} '
              'ingredient "${ing.id}"'));
        }
      }
    }
    return issues;
  }

  /// Ingredients whose nutrition values are still unverified estimates.
  List<Ingredient> get unverified => ingredients.values
      .where((i) => i.source == NutritionSource.est)
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
}
