/// What is in the kitchen, day by day: when each ingredient is bought, how
/// much of it is used, and what goes off before it is eaten.
///
/// The same ledger serves two purposes. The planner consults it while building
/// the week, so it prefers cooking from what is already open and keeps
/// perishables inside their shelf life. Replaying a finished plan through it
/// then gives the shopping trips — what to buy on which day — and any food the
/// plan would still waste.
///
/// Buying is lazy: an ingredient is bought only when a meal first needs it, on
/// the most recent shop at which it would still be fresh on the day it is
/// cooked. Buying whole packs leaves remainders; those stay in the ledger with
/// their own use-by day, and later meals draw on them first.
library;

import 'dart:math' as math;

import '../models/food.dart';
import '../models/plan.dart';
import '../models/profile.dart';

const _eps = 1e-6;

/// One purchase of one ingredient.
class Purchase {
  Purchase({
    required this.ingredientId,
    required this.day,
    required this.packs,
    required this.qty,
    this.topUp = false,
    this.used = 0,
  });

  final String ingredientId;

  /// Day offset into the week on which it is bought.
  final int day;
  final int packs;

  /// Quantity bought, in the ingredient's base unit.
  final double qty;

  /// Bought on a day that is not one of the household's usual shops, because
  /// the plan could not be covered any other way.
  final bool topUp;

  /// How much of this purchase the plan cooks with.
  double used;

  Map<String, dynamic> toJson() => {
        'id': ingredientId,
        'day': day,
        'packs': packs,
        'qty': qty,
        'topUp': topUp,
      };

  static Purchase fromJson(Map<String, dynamic> j) => Purchase(
        ingredientId: j['id'] as String,
        day: j['day'] as int,
        packs: j['packs'] as int,
        qty: (j['qty'] as num).toDouble(),
        topUp: j['topUp'] as bool? ?? false,
      );
}

/// Part of a purchase still sitting in the kitchen.
class _Lot {
  _Lot(this.purchase, this.remaining, this.goodUntil);
  final Purchase purchase;
  double remaining;
  final int goodUntil;
}

/// Food that went off before anyone cooked it.
class Spoilage {
  const Spoilage({
    required this.ingredientId,
    required this.qty,
    required this.boughtDay,
    required this.goodUntil,
  });
  final String ingredientId;
  final double qty;
  final int boughtDay;
  final int goodUntil;
}

/// What drawing an ingredient from the kitchen on a given day would involve.
class UseQuote {
  const UseQuote({
    required this.fromStock,
    required this.fromExpiring,
    required this.leftover,
    required this.leftoverGoodUntil,
    required this.topUp,
  });

  /// Covered by food already bought.
  final double fromStock;

  /// Of [fromStock], how much would otherwise go off by tomorrow.
  final double fromExpiring;

  /// Remainder of any newly opened packs.
  final double leftover;
  final int leftoverGoodUntil;

  /// Needs a shop outside the household's usual rhythm.
  final bool topUp;
}

class StockLedger {
  StockLedger({
    required this.ingredients,
    required this.profile,
    this.frozenThrough = -1,
    Iterable<Purchase> alreadyBought = const [],
  }) {
    for (final p in alreadyBought) {
      final copy = Purchase(
        ingredientId: p.ingredientId,
        day: p.day,
        packs: p.packs,
        qty: p.qty,
        topUp: p.topUp,
      );
      purchases.add(copy);
      final ing = ingredients[p.ingredientId];
      if (ing == null) continue;
      (_lots[p.ingredientId] ??= [])
          .add(_Lot(copy, copy.qty, ing.goodUntil(copy.day)));
    }
  }

  final Map<String, Ingredient> ingredients;
  final Profile profile;

  /// Days up to and including this one have already happened: their shops are
  /// done and nothing more can be bought on them.
  final int frozenThrough;

  final List<Purchase> purchases = [];
  final List<Spoilage> spoiled = [];

  /// Daily-fresh items (milk), bought each day in the amount needed.
  final Map<String, List<double>> dailyFresh = {};

  final Map<String, List<_Lot>> _lots = {};

  /// Whether the ledger follows this ingredient at all. Spices and oils the
  /// household keeps, and anything marked as already owned, are assumed to be
  /// in the kitchen.
  bool tracks(String id) {
    final ing = ingredients[id];
    if (ing == null) return false;
    return !ing.pantryStaple && !ing.dailyFresh && !profile.pantry.contains(id);
  }

  /// Quantity of [id] bought and still good on [day].
  double onHand(String id, int day) {
    var q = 0.0;
    for (final l in _lots[id] ?? const <_Lot>[]) {
      if (l.goodUntil >= day) q += l.remaining;
    }
    return q;
  }

  /// Ingredient ids with food still good on [day].
  Iterable<String> stockedOn(int day) sync* {
    for (final e in _lots.entries) {
      if (e.value.any((l) => l.goodUntil >= day && l.remaining > _eps)) {
        yield e.key;
      }
    }
  }

  /// The shop a purchase needed on [day] would be made at, or null when it
  /// would take an extra trip.
  int? _shopFor(Ingredient ing, int day) {
    final trips = profile.shopping.tripDays.where((t) => t > frozenThrough);
    int? best;
    for (final t in trips) {
      if (t <= day && ing.goodUntil(t) >= day) best = t;
    }
    return best;
  }

  /// What using [qty] of [id] on [day] would involve, without doing it.
  UseQuote quote(String id, double qty, int day) {
    final ing = ingredients[id]!;
    var need = qty;
    var fromStock = 0.0;
    var fromExpiring = 0.0;
    for (final l in _sorted(id, day)) {
      if (need <= _eps) break;
      final take = math.min(need, l.remaining);
      fromStock += take;
      if (l.goodUntil <= day + 1 && ing.perishable) fromExpiring += take;
      need -= take;
    }
    if (need <= _eps) {
      return UseQuote(
        fromStock: fromStock,
        fromExpiring: fromExpiring,
        leftover: 0,
        leftoverGoodUntil: day,
        topUp: false,
      );
    }
    final shop = _shopFor(ing, day);
    final boughtOn = shop ?? day;
    final packs = (need / ing.packSize).ceil();
    return UseQuote(
      fromStock: fromStock,
      fromExpiring: fromExpiring,
      leftover: packs * ing.packSize - need,
      leftoverGoodUntil: ing.goodUntil(boughtOn),
      topUp: shop == null,
    );
  }

  /// Take [qty] of [id] out of the kitchen on [day], buying what is missing.
  ///
  /// With [canBuy] false the shortfall is simply not recorded — used when
  /// replaying days that have already happened, whose shops are fixed.
  void use(String id, double qty, int day, {bool canBuy = true}) {
    final ing = ingredients[id];
    if (ing == null || qty <= _eps) return;
    if (ing.dailyFresh && !profile.pantry.contains(id)) {
      final perDay = dailyFresh[id] ??= List.filled(7, 0.0);
      if (day >= 0 && day < 7) perDay[day] += qty;
      return;
    }
    if (!tracks(id)) return;

    var need = qty;
    for (final l in _sorted(id, day)) {
      if (need <= _eps) break;
      final take = math.min(need, l.remaining);
      l.remaining -= take;
      l.purchase.used += take;
      need -= take;
    }
    if (need <= _eps || !canBuy || day <= frozenThrough) return;

    final shop = _shopFor(ing, day);
    final boughtOn = shop ?? day;
    final packs = (need / ing.packSize).ceil();
    final p = Purchase(
      ingredientId: id,
      day: boughtOn,
      packs: packs,
      qty: packs * ing.packSize,
      topUp: shop == null,
      used: need,
    );
    purchases.add(p);
    (_lots[id] ??= []).add(_Lot(p, p.qty - need, ing.goodUntil(boughtOn)));
  }

  /// Close [day]: anything that is not good tomorrow has spoiled.
  void endDay(int day) {
    for (final e in _lots.entries) {
      for (final l in e.value) {
        if (l.goodUntil == day && l.remaining > 1) {
          spoiled.add(Spoilage(
            ingredientId: e.key,
            qty: l.remaining,
            boughtDay: l.purchase.day,
            goodUntil: l.goodUntil,
          ));
        }
      }
      e.value.removeWhere((l) => l.goodUntil <= day || l.remaining <= _eps);
    }
  }

  /// Oldest-expiring first, so nothing is left to go off behind fresher stock.
  List<_Lot> _sorted(String id, int day) => [
        for (final l in _lots[id] ?? const <_Lot>[])
          if (l.goodUntil >= day && l.remaining > _eps) l
      ]..sort((a, b) => a.goodUntil.compareTo(b.goodUntil));

  /// Total spoiled, per ingredient.
  Map<String, double> get wasted {
    final out = <String, double>{};
    for (final s in spoiled) {
      out[s.ingredientId] = (out[s.ingredientId] ?? 0) + s.qty;
    }
    return out;
  }

  /// Share of a pack, summed over every spoiled lot — a unit-free measure of
  /// how much the plan wastes, so 100 g of coriander counts like 100 g of a
  /// 1 kg bag of potatoes would not.
  double get wasteScore => spoiled.fold(
      0.0, (a, s) => a + s.qty / ingredients[s.ingredientId]!.packSize);

  /// Run a whole week through a fresh ledger.
  ///
  /// Days up to [frozenThrough] replay what was actually used (from
  /// [feedback]) against the shops already made in [alreadyBought]; later
  /// days follow [plan] and buy whatever they need.
  static StockLedger replay({
    required WeekPlan plan,
    required Map<String, Ingredient> ingredients,
    required Profile profile,
    Map<int, DayFeedback> feedback = const {},
    Iterable<Purchase> alreadyBought = const [],
    int frozenThrough = -1,
  }) {
    final ledger = StockLedger(
      ingredients: ingredients,
      profile: profile,
      frozenThrough: frozenThrough,
      alreadyBought: alreadyBought,
    );
    for (final day in plan.days) {
      final d = day.dayIndex;
      final fb = feedback[d];
      final used = fb != null ? fb.used(day) : _plannedUse(day);
      for (final e in used.entries) {
        ledger.use(e.key, e.value, d, canBuy: d > frozenThrough);
      }
      ledger.endDay(d);
    }
    return ledger;
  }

  static Map<String, double> _plannedUse(DayPlan day) {
    final out = <String, double>{};
    for (final m in day.meals) {
      m.ingredientQuantities().forEach((id, q) {
        out[id] = (out[id] ?? 0) + q;
      });
    }
    return out;
  }
}
