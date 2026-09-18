/// Ingredient and recipe models, plus the [Nutrients] vector used everywhere.
library;

import 'profile.dart';

/// A nutrient vector. Additive and scalable so meals, days and weeks compose.
class Nutrients {
  const Nutrients({
    this.kcal = 0,
    this.protein = 0,
    this.fat = 0,
    this.carb = 0,
    this.fibre = 0,
    this.iron = 0,
    this.calcium = 0,
  });

  final double kcal;
  final double protein;
  final double fat;
  final double carb;
  final double fibre;
  final double iron;
  final double calcium;

  static const zero = Nutrients();

  Nutrients operator +(Nutrients o) => Nutrients(
        kcal: kcal + o.kcal,
        protein: protein + o.protein,
        fat: fat + o.fat,
        carb: carb + o.carb,
        fibre: fibre + o.fibre,
        iron: iron + o.iron,
        calcium: calcium + o.calcium,
      );

  Nutrients operator -(Nutrients o) => Nutrients(
        kcal: kcal - o.kcal,
        protein: protein - o.protein,
        fat: fat - o.fat,
        carb: carb - o.carb,
        fibre: fibre - o.fibre,
        iron: iron - o.iron,
        calcium: calcium - o.calcium,
      );

  Nutrients operator *(double f) => Nutrients(
        kcal: kcal * f,
        protein: protein * f,
        fat: fat * f,
        carb: carb * f,
        fibre: fibre * f,
        iron: iron * f,
        calcium: calcium * f,
      );

  static Nutrients sum(Iterable<Nutrients> xs) =>
      xs.fold(zero, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
        'kcal': kcal,
        'protein': protein,
        'fat': fat,
        'carb': carb,
        'fibre': fibre,
        'iron': iron,
        'calcium': calcium,
      };

  static Nutrients fromJson(Map<String, dynamic> j) => Nutrients(
        kcal: (j['kcal'] as num?)?.toDouble() ?? 0,
        protein: (j['protein'] as num?)?.toDouble() ?? 0,
        fat: (j['fat'] as num?)?.toDouble() ?? 0,
        carb: (j['carb'] as num?)?.toDouble() ?? 0,
        fibre: (j['fibre'] as num?)?.toDouble() ?? 0,
        iron: (j['iron'] as num?)?.toDouble() ?? 0,
        calcium: (j['calcium'] as num?)?.toDouble() ?? 0,
      );

  @override
  String toString() => 'Nutrients(kcal: ${kcal.toStringAsFixed(0)}, '
      'P: ${protein.toStringAsFixed(1)}g, '
      'F: ${fat.toStringAsFixed(1)}g, '
      'C: ${carb.toStringAsFixed(1)}g)';
}

/// Supermarket aisle, used to group the shopping list.
enum Aisle {
  grains('Grains & Atta'),
  pulses('Pulses & Dals'),
  vegetables('Vegetables'),
  fruits('Fruits'),
  dairy('Dairy'),
  eggmeat('Egg & Meat'),
  nuts('Nuts & Seeds'),
  spices('Masala & Spices'),
  oils('Oils & Ghee'),
  other('Other');

  const Aisle(this.label);
  final String label;

  static Aisle parse(String s) => Aisle.values.firstWhere(
        (a) => a.name == s,
        orElse: () => Aisle.other,
      );
}

/// Where a nutrition value came from. Surfaced in the UI so users can judge it.
enum NutritionSource {
  ifct2017('IFCT 2017 (ICMR-NIN)'),
  usda('USDA FoodData Central'),
  productLabel('Product label'),
  est('Estimate — pending verification');

  const NutritionSource(this.description);

  /// Human-readable provenance, shown next to nutrition figures in the app.
  final String description;

  static NutritionSource parse(String s) {
    // 'label' is the value used in the seed JSON for commercial products.
    if (s == 'label') return NutritionSource.productLabel;
    return NutritionSource.values.firstWhere(
      (a) => a.name == s,
      orElse: () => NutritionSource.est,
    );
  }
}

/// What an ingredient is nutritionally *for*.
///
/// The shopping list is ultimately about having the right materials in the
/// kitchen to cook balanced meals, so grouping by nutritional function tells
/// you more than grouping by shop aisle does.
enum NutrientRole {
  protein('Protein foods', 'Dals, paneer, tofu, soya, egg and meat — the '
      'hardest target to hit, and the reason the week is planned at all.'),
  grain('Grains & staples', 'Atta, rice and millets. Your main source of '
      'energy, and a real contributor of protein and iron in Indian diets.'),
  vegetable('Vegetables', 'Fibre, folate and micronutrients. Variety matters '
      'more here than quantity of any one vegetable.'),
  fruit('Fruit', 'Fibre and vitamin C, which also helps you absorb iron from '
      'the dals and greens in the same meal.'),
  dairy('Dairy', 'Milk and curd carry most of your calcium.'),
  nuts('Nuts & seeds', 'Concentrated protein, healthy fat and — for til and '
      'almonds — a lot of calcium.'),
  fat('Fats & oils', 'Energy density and fat-soluble vitamins. Needed, but '
      'the easiest thing to overdo.'),
  flavour('Flavour & spices', 'Little nutritional weight at the quantities '
      'used, but they are what make the food worth eating.');

  const NutrientRole(this.label, this.why);
  final String label;
  final String why;
}

class Ingredient {
  const Ingredient({
    required this.id,
    required this.name,
    required this.aisle,
    required this.unit,
    required this.per100,
    required this.packSize,
    required this.pantryStaple,
    required this.diet,
    required this.source,
    this.pieceGrams,
    this.note,
    this.shelfLifeDays = 180,
    this.dailyFresh = false,
  });

  final String id;
  final String name;
  final Aisle aisle;

  /// 'g' or 'ml'.
  final String unit;

  /// Nutrients per 100 g / 100 ml of the raw item.
  final Nutrients per100;

  /// Typical market pack size in [unit]; shopping quantities round up to this.
  final double packSize;

  /// Spices and oils the household almost certainly already owns.
  final bool pantryStaple;

  final DietType diet;
  final NutritionSource source;

  /// For countable items (eggs, bananas) — grams per piece, for display.
  final double? pieceGrams;

  final String? note;

  /// Days the item stays good after purchase, stored the usual way — in the
  /// fridge for dairy, meat and greens. Bought on day 0 with a shelf life of 2,
  /// it can be cooked on days 0 and 1.
  final int shelfLifeDays;

  /// Bought fresh every day (milk from the doodhwala) rather than stocked for
  /// the week, so it is never at risk of spoiling in the fridge.
  final bool dailyFresh;

  /// Would go off within a week if bought on the weekly shop.
  bool get perishable => !dailyFresh && shelfLifeDays < 7;

  /// Last day offset on which a purchase made on [boughtDay] is still good.
  int goodUntil(int boughtDay) => boughtDay + shelfLifeDays - 1;

  Nutrients nutrientsFor(double qty) => per100 * (qty / 100.0);

  /// Classify by what the ingredient mainly contributes.
  ///
  /// Aisle is the starting point, but protein density decides the dairy case:
  /// paneer and tofu belong with the protein foods, milk and curd with the
  /// calcium sources.
  NutrientRole get role {
    if (pantryStaple && (aisle == Aisle.spices || aisle == Aisle.vegetables)) {
      return NutrientRole.flavour;
    }
    switch (aisle) {
      case Aisle.pulses:
      case Aisle.eggmeat:
        return NutrientRole.protein;
      case Aisle.dairy:
        return per100.protein >= 12
            ? NutrientRole.protein
            : NutrientRole.dairy;
      case Aisle.grains:
        return NutrientRole.grain;
      case Aisle.vegetables:
        return NutrientRole.vegetable;
      case Aisle.fruits:
        return NutrientRole.fruit;
      case Aisle.nuts:
        return NutrientRole.nuts;
      case Aisle.oils:
        return NutrientRole.fat;
      case Aisle.spices:
        return NutrientRole.flavour;
      case Aisle.other:
        return NutrientRole.flavour;
    }
  }

  static Ingredient fromJson(Map<String, dynamic> j) {
    final p = j['per100'] as Map<String, dynamic>;
    return Ingredient(
      id: j['id'] as String,
      name: j['name'] as String,
      aisle: Aisle.parse(j['aisle'] as String),
      unit: j['unit'] as String,
      per100: Nutrients.fromJson(p),
      packSize: (j['packSize'] as num).toDouble(),
      pantryStaple: j['pantryStaple'] as bool? ?? false,
      diet: DietType.values.byName(j['diet'] as String? ?? 'veg'),
      source: NutritionSource.parse(j['src'] as String? ?? 'est'),
      pieceGrams: (j['pieceGrams'] as num?)?.toDouble(),
      note: j['note'] as String?,
      shelfLifeDays: j['shelfLifeDays'] as int? ?? 180,
      dailyFresh: j['dailyFresh'] as bool? ?? false,
    );
  }
}

/// How a recipe functions within a meal.
enum RecipeRole {
  /// Eaten on its own — breakfasts, one-dish meals, snacks.
  complete,

  /// The protein centre of a lunch or dinner — a dal, paneer, egg or meat dish.
  main,

  /// A vegetable dish that accompanies the main. Nutritionally useful, but it
  /// is not the protein source, so it can never stand in for a `main`.
  sabzi,

  /// Roti or rice. Portion is varied by the planner to close the energy gap.
  staple,

  /// Curd, salad, small accompaniment.
  side;

  static RecipeRole parse(String s) =>
      RecipeRole.values.firstWhere((r) => r.name == s,
          orElse: () => RecipeRole.main);
}

enum MealType {
  breakfast('Breakfast'),
  lunch('Lunch'),
  dinner('Dinner'),
  snack('Snack');

  const MealType(this.label);
  final String label;

  static MealType parse(String s) =>
      MealType.values.firstWhere((m) => m.name == s,
          orElse: () => MealType.lunch);
}

class RecipeLine {
  const RecipeLine(this.ingredientId, this.qty);
  final String ingredientId;

  /// Quantity in the ingredient's base unit, for the recipe's stated servings.
  final double qty;
}

class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.role,
    required this.slots,
    required this.diet,
    required this.servings,
    required this.prepMin,
    required this.lines,
    required this.tags,
    this.scalable = false,
    this.portionUnit,
  });

  final String id;
  final String name;
  final RecipeRole role;
  final Set<MealType> slots;
  final DietType diet;

  /// How many servings the quantities in [lines] produce.
  final int servings;
  final int prepMin;
  final List<RecipeLine> lines;
  final Set<String> tags;

  /// Staples only: the planner may vary the portion continuously.
  final bool scalable;

  /// Display unit for a scalable staple — 'roti', 'katori'.
  final String? portionUnit;

  Set<String> get ingredientIds => {for (final l in lines) l.ingredientId};

  /// Nutrients for exactly one serving.
  Nutrients perServing(Map<String, Ingredient> byId) {
    var total = Nutrients.zero;
    for (final l in lines) {
      final ing = byId[l.ingredientId];
      if (ing == null) continue;
      total += ing.nutrientsFor(l.qty);
    }
    return total * (1.0 / servings);
  }

  static Recipe fromJson(Map<String, dynamic> j) => Recipe(
        id: j['id'] as String,
        name: j['name'] as String,
        role: RecipeRole.parse(j['role'] as String),
        slots: {
          for (final s in (j['slots'] as List).cast<String>()) MealType.parse(s)
        },
        diet: DietType.values.byName(j['diet'] as String),
        servings: j['servings'] as int,
        prepMin: j['prepMin'] as int,
        scalable: j['scalable'] as bool? ?? false,
        portionUnit: j['portionUnit'] as String?,
        tags: {...(j['tags'] as List? ?? []).cast<String>()},
        lines: [
          for (final l in (j['ingredients'] as List).cast<Map<String, dynamic>>())
            RecipeLine(l['id'] as String, (l['qty'] as num).toDouble())
        ],
      );
}

/// Which ingredients an [AvoidGroup] rules out.
extension AvoidGroupMatch on AvoidGroup {
  bool covers(Ingredient i) => switch (this) {
        AvoidGroup.nonVeg => i.diet != DietType.veg,
        AvoidGroup.meat => i.diet == DietType.nonveg && !_isSeafood(i),
        AvoidGroup.chicken => i.id.startsWith('chicken'),
        AvoidGroup.fish => i.diet == DietType.nonveg && _isSeafood(i),
        AvoidGroup.egg => i.diet == DietType.egg,
        AvoidGroup.dairy => const {
            'milk',
            'curd',
            'paneer',
            'butter',
            'ghee',
            'hung_curd',
          }.contains(i.id),
        AvoidGroup.pulses => i.aisle == Aisle.pulses || i.id == 'besan',
        AvoidGroup.grains => i.aisle == Aisle.grains && i.id != 'besan',
        AvoidGroup.riceWheat => const {
            'atta',
            'rice_raw',
            'brown_rice',
            'poha',
            'rava',
            'idli_rava',
            'bread_brown',
          }.contains(i.id),
        AvoidGroup.onionGarlic => const {'onion', 'garlic'}.contains(i.id),
        AvoidGroup.nuts => i.aisle == Aisle.nuts,
      };

  /// Whether the group matches what someone typed: by its name, what it
  /// holds, or another word for it — so "dairy", "diary" and "doodh" all find
  /// Dairy.
  bool matchesSearch(String query) {
    final q = _searchKey(query);
    if (q.isEmpty) return true;
    return [label, description, ...aliases].any((t) => _searchKey(t).contains(q));
  }

  /// Whether [selected] already rules out everything this group would, so
  /// ticking it too would add nothing — "Chicken" once "All non-veg" is on.
  bool isImpliedBy(Set<AvoidGroup> selected, Iterable<Ingredient> foods) {
    if (selected.contains(this)) return false;
    final mine = foods.where(covers).toList();
    return mine.isNotEmpty &&
        mine.every((i) => selected.any((g) => g.covers(i)));
  }
}

/// Lower case with spaces and punctuation dropped, so "non-veg", "non veg"
/// and "nonveg" compare equal.
String _searchKey(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

bool _isSeafood(Ingredient i) =>
    const ['fish', 'prawn', 'shrimp', 'crab'].any(i.id.startsWith);

/// Whether [i] matches what someone typed into a search box — by name,
/// including the English or Hindi name in brackets, or by id.
bool matchesSearch(Ingredient i, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return i.name.toLowerCase().contains(q) ||
      i.id.replaceAll('_', ' ').contains(q);
}
