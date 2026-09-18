/// Turns a week's plan into a shopping list you can actually take to the shop.
///
/// Two things make this more than a sum: quantities are rounded up to real
/// market pack sizes, and pantry staples the household already owns are split
/// into a separate "check you have" group rather than padding the buy list.
///
/// The list is also split into shopping trips. Anything that keeps is bought
/// on the first shop; perishables are bought on the shop just before they are
/// cooked, in amounts that get used before they go off. Milk is listed as a
/// daily amount, since it is bought fresh each morning.
library;

import 'dart:math' as math;

import '../models/food.dart';
import '../models/plan.dart';
import '../models/profile.dart';
import 'stock.dart';

class ShoppingItem {
  const ShoppingItem({
    required this.ingredient,
    required this.neededQty,
    required this.buyQty,
    required this.packs,
  });

  final Ingredient ingredient;

  /// What the week's recipes actually consume, in base units.
  final double neededQty;

  /// What you end up buying once rounded to whole packs.
  final double buyQty;
  final int packs;

  Aisle get aisle => ingredient.aisle;
  NutrientRole get role => ingredient.role;

  /// Nutrients this item contributes to the week, based on the quantity the
  /// cooking actually uses.
  Nutrients get contribution => ingredient.nutrientsFor(neededQty);

  /// "750 g", "1.5 kg", "2 × 500 ml".
  String get quantityLabel => _formatQty(buyQty, ingredient.unit);

  /// Shown as secondary text when buying more than the recipes need.
  String? get overageLabel {
    if (buyQty <= neededQty * 1.05) return null;
    // Rounded like a kitchen scale reads: 281.3 g is "about 280 g".
    final step = neededQty < 100 ? 5.0 : (neededQty < 1000 ? 10.0 : 50.0);
    final rounded = math.max(step, (neededQty / step).round() * step);
    return 'the week uses about ${_formatQty(rounded, ingredient.unit)}';
  }

  static String _formatQty(double qty, String unit) {
    if (unit == 'ml') {
      if (qty >= 1000) {
        final l = qty / 1000;
        return '${_trim(l)} L';
      }
      return '${_trim(qty)} ml';
    }
    if (qty >= 1000) {
      final kg = qty / 1000;
      return '${_trim(kg)} kg';
    }
    return '${_trim(qty)} g';
  }

  static String _trim(double v) {
    if ((v - v.roundToDouble()).abs() < 0.01) return v.round().toString();
    return v.toStringAsFixed(v < 10 ? 2 : 1).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
}

/// Everything to buy on one day.
class ShoppingTrip {
  const ShoppingTrip({required this.day, required this.items, this.topUp = false});

  /// Day offset into the week.
  final int day;
  final List<ShoppingItem> items;

  /// A shop the household would not usually make, needed to keep the plan
  /// fresh.
  final bool topUp;

  Map<Aisle, List<ShoppingItem>> get byAisle {
    final out = <Aisle, List<ShoppingItem>>{};
    for (final i in items) {
      (out[i.aisle] ??= []).add(i);
    }
    return {
      for (final a in Aisle.values)
        if (out[a] != null) a: out[a]!,
    };
  }

  /// Key for remembering that an item on this trip has been bought.
  String keyFor(ShoppingItem item) => '$day:${item.ingredient.id}';
}

/// An item bought fresh each day rather than stocked.
class DailyItem {
  const DailyItem(this.ingredient, this.perDay);
  final Ingredient ingredient;

  /// Quantity needed on each day of the week, in base units.
  final List<double> perDay;

  double get typical {
    final used = perDay.where((q) => q > 0).toList();
    if (used.isEmpty) return 0;
    return used.reduce((a, b) => a + b) / used.length;
  }
}

class ShoppingList {
  const ShoppingList({
    required this.toBuy,
    required this.pantryCheck,
    required this.excludedOwned,
    this.trips = const [],
    this.daily = const [],
    this.spoilage = const [],
  });

  /// The shops, in date order. Every item in [toBuy] except the daily ones is
  /// bought on one of these.
  final List<ShoppingTrip> trips;

  /// Bought fresh each day.
  final List<DailyItem> daily;

  /// Food the plan still cannot use before it goes off. Usually empty or a
  /// few grams; shown rather than hidden.
  final List<Spoilage> spoilage;

  /// Items to buy, grouped by aisle. Aisle order follows [Aisle.values], which
  /// is roughly the order you walk a shop.
  final Map<Aisle, List<ShoppingItem>> toBuy;

  /// Spices and oils the household very likely already has — worth checking,
  /// not worth buying weekly.
  final List<ShoppingItem> pantryCheck;

  /// Ingredients dropped entirely because the user said they already have them.
  final List<Ingredient> excludedOwned;

  int get itemCount => toBuy.values.fold(0, (a, b) => a + b.length);

  /// Every item in the list, buy-list and pantry check together.
  Iterable<ShoppingItem> get allItems sync* {
    for (final items in toBuy.values) {
      yield* items;
    }
    yield* pantryCheck;
  }

  /// The same items grouped by what they nutritionally contribute, rather than
  /// by shop aisle. This is the view that answers "why is this on my list?".
  Map<NutrientRole, List<ShoppingItem>> get byNutrientRole {
    final out = <NutrientRole, List<ShoppingItem>>{};
    for (final item in allItems) {
      (out[item.ingredient.role] ??= []).add(item);
    }
    for (final list in out.values) {
      list.sort((a, b) => b.contribution.protein.compareTo(a.contribution.protein));
    }
    return out;
  }

  List<NutrientRole> get orderedRoles => NutrientRole.values
      .where((r) => byNutrientRole[r]?.isNotEmpty ?? false)
      .toList();

  /// What the week's ingredients actually supply.
  ///
  /// Based on the quantities the cooking consumes, not the rounded-up pack
  /// sizes — buying a 1 kg bag to use 750 g does not feed you 1 kg.
  Nutrients get provides =>
      Nutrients.sum(allItems.map((i) => i.contribution));

  /// Supply as a fraction of what the household needs for the week.
  Nutrients coverageAgainst(Nutrients weeklyNeed) => Nutrients(
        kcal: _ratio(provides.kcal, weeklyNeed.kcal),
        protein: _ratio(provides.protein, weeklyNeed.protein),
        fat: _ratio(provides.fat, weeklyNeed.fat),
        carb: _ratio(provides.carb, weeklyNeed.carb),
        fibre: _ratio(provides.fibre, weeklyNeed.fibre),
        iron: _ratio(provides.iron, weeklyNeed.iron),
        calcium: _ratio(provides.calcium, weeklyNeed.calcium),
      );

  static double _ratio(double got, double need) => need <= 0 ? 1 : got / need;

  /// Fraction of the week's protein that comes from cereals rather than from
  /// dals, dairy, soya, egg or meat.
  ///
  /// Worth surfacing: in a typical Indian vegetarian week grains supply as much
  /// protein as the dals do, and cereal protein is less digestible. A high
  /// share here is the practical reason ICMR-NIN raises the requirement for
  /// cereal-based diets, and it points at the fix — more dal, paneer or soya
  /// rather than more roti.
  double get cerealProteinShare {
    final total = provides.protein;
    if (total <= 0) return 0;
    final cereal = allItems
        .where((i) => i.ingredient.role == NutrientRole.grain)
        .fold(0.0, (a, i) => a + i.contribution.protein);
    return cereal / total;
  }

  List<Aisle> get orderedAisles =>
      Aisle.values.where((a) => toBuy[a]?.isNotEmpty ?? false).toList();

  /// Plain-text rendering for the "share list" action.
  ///
  /// [dayLabel] names a day offset for the trip headings — the engine does
  /// not know dates.
  String toShareText({String Function(int day)? dayLabel}) {
    final label = dayLabel ?? (d) => 'Day ${d + 1}';
    final b = StringBuffer('Shopping list\n');
    for (final trip in trips) {
      if (trips.length > 1) b.writeln('\n== ${label(trip.day)} ==');
      trip.byAisle.forEach((aisle, items) {
        b.writeln('\n${aisle.label}');
        for (final it in items) {
          b.writeln('  - ${it.ingredient.name} — ${it.quantityLabel}');
        }
      });
    }
    if (daily.isNotEmpty) {
      b.writeln('\nEvery day');
      for (final d in daily) {
        b.writeln('  - ${d.ingredient.name} — about '
            '${ShoppingItem._formatQty(d.typical.roundToDouble(), d.ingredient.unit)}');
      }
    }
    if (pantryCheck.isNotEmpty) {
      b.writeln('\nCheck you have');
      for (final it in pantryCheck) {
        b.writeln('  - ${it.ingredient.name}');
      }
    }
    return b.toString();
  }
}

/// Build the shopping list for [plan].
///
/// [Profile.pantry] removes items outright. Ingredients flagged
/// `pantryStaple` are moved to [ShoppingList.pantryCheck] instead of the buy
/// list, because a list that tells you to buy turmeric every week is a list
/// people stop trusting.
///
/// [stock] is the week run through the kitchen; by default the plan is
/// replayed from an empty one. Pass the ledger from a week in progress so
/// shops already made are shown as they were.
ShoppingList buildShoppingList({
  required WeekPlan plan,
  required Map<String, Ingredient> ingredients,
  required Profile profile,
  StockLedger? stock,
}) {
  final ledger = stock ??
      StockLedger.replay(plan: plan, ingredients: ingredients, profile: profile);
  final totals = plan.ingredientTotals();

  // Purchases per trip, merged per ingredient.
  final perTrip = <int, Map<String, ({int packs, double qty, double used, bool topUp})>>{};
  final boughtTotal = <String, ({int packs, double qty})>{};
  for (final p in ledger.purchases) {
    final trip = perTrip[p.day] ??= {};
    final prev = trip[p.ingredientId];
    trip[p.ingredientId] = (
      packs: (prev?.packs ?? 0) + p.packs,
      qty: (prev?.qty ?? 0) + p.qty,
      used: (prev?.used ?? 0) + p.used,
      topUp: (prev?.topUp ?? false) || p.topUp,
    );
    final t = boughtTotal[p.ingredientId];
    boughtTotal[p.ingredientId] =
        (packs: (t?.packs ?? 0) + p.packs, qty: (t?.qty ?? 0) + p.qty);
  }

  final toBuy = <Aisle, List<ShoppingItem>>{};
  final pantryCheck = <ShoppingItem>[];
  final excluded = <Ingredient>[];

  final sortedIds = totals.keys.toList()..sort();

  for (final id in sortedIds) {
    final qty = totals[id]!;
    final ing = ingredients[id];
    if (ing == null || qty <= 0) continue;

    if (profile.pantry.contains(id)) {
      excluded.add(ing);
      continue;
    }

    // Bought across the trips when the ledger follows it; otherwise (spices,
    // oils, milk) the week's need rounded up to whole packs.
    final bought = boughtTotal[id];
    final packs = bought?.packs ?? math.max(1, (qty / ing.packSize).ceil());
    final item = ShoppingItem(
      ingredient: ing,
      neededQty: qty,
      buyQty: math.max(bought?.qty ?? 0, packs * ing.packSize),
      packs: packs,
    );

    if (ing.pantryStaple) {
      pantryCheck.add(item);
    } else {
      (toBuy[ing.aisle] ??= []).add(item);
    }
  }

  for (final list in toBuy.values) {
    list.sort((a, b) => a.ingredient.name.compareTo(b.ingredient.name));
  }
  pantryCheck.sort((a, b) => a.ingredient.name.compareTo(b.ingredient.name));

  final trips = <ShoppingTrip>[
    for (final day in perTrip.keys.toList()..sort())
      ShoppingTrip(
        day: day,
        topUp: perTrip[day]!.values.every((e) => e.topUp),
        items: [
          for (final e in perTrip[day]!.entries)
            if (ingredients[e.key] != null)
              ShoppingItem(
                ingredient: ingredients[e.key]!,
                neededQty: e.value.used,
                buyQty: e.value.qty,
                packs: e.value.packs,
              ),
        ]..sort((a, b) => a.ingredient.name.compareTo(b.ingredient.name)),
      ),
  ];

  final daily = [
    for (final e in ledger.dailyFresh.entries)
      if (ingredients[e.key] != null) DailyItem(ingredients[e.key]!, e.value),
  ];

  return ShoppingList(
    toBuy: toBuy,
    pantryCheck: pantryCheck,
    excludedOwned: excluded,
    trips: trips,
    daily: daily,
    spoilage: ledger.spoiled,
  );
}
