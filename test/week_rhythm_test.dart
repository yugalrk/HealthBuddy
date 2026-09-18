import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbuddy/data/food_data.dart';
import 'package:healthbuddy/engine/adapt.dart';
import 'package:healthbuddy/engine/planner.dart';
import 'package:healthbuddy/engine/shopping_list.dart';
import 'package:healthbuddy/engine/stock.dart';
import 'package:healthbuddy/models/food.dart';
import 'package:healthbuddy/models/plan.dart';
import 'package:healthbuddy/models/profile.dart';

FoodData loadSeed() => FoodData.parse(
      ingredientsJson: File('assets/seed/ingredients.json').readAsStringSync(),
      recipesJson: File('assets/seed/recipes.json').readAsStringSync(),
    );

const _adult = HouseholdMember(
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

final _family = [
  _adult,
  const HouseholdMember(
    id: 'b',
    name: 'b',
    age: 29,
    sex: Sex.female,
    weightKg: 58,
    heightCm: 162,
    activity: ActivityLevel.light,
    goal: Goal.maintain,
  ),
  HouseholdMember.reference(id: 'c', name: 'c', age: 14, sex: Sex.male),
  HouseholdMember.reference(id: 'd', name: 'd', age: 8, sex: Sex.female),
];

void main() {
  late FoodData data;
  setUpAll(() => data = loadSeed());

  WeekPlan plan(Profile p, {int seed = 3, int startWeekday = 0}) =>
      generateBalancedWeek(
        profile: p,
        recipes: data.recipes,
        ingredients: data.ingredients,
        seed: seed,
        startWeekday: startWeekday,
      );

  Set<String> idsOn(DayPlan d) => {
        for (final m in d.meals)
          for (final c in m.components) ...c.recipe.ingredientIds
      };

  group('weekly observances', () {
    test('no meat or eggs on the days someone gives them up', () {
      final p = Profile(members: _family, diet: DietType.nonveg, dayRules: [
        const DayRule(
          memberIds: {'b'},
          weekdays: {1, 3, 5},
          groups: {AvoidGroup.nonVeg},
        ),
      ]);
      for (var seed = 0; seed < 4; seed++) {
        for (final d in plan(p, seed: seed).days) {
          if (!const {1, 3, 5}.contains(d.weekday)) continue;
          final ids = idsOn(d);
          expect(
              ids.any((id) => data.ingredients[id]!.diet != DietType.veg),
              isFalse,
              reason: '${d.dayName}: $ids');
        }
      }

      // Only those days: the rest of the week may still have them.
      final planner = MealPlanner(
          profile: p, recipes: data.recipes, ingredients: data.ingredients);
      expect(planner.excludedOn(1),
          containsAll(['egg', 'chicken_breast', 'fish_rohu']));
      expect(planner.excludedOn(0), isEmpty);
    });

    test('each non-veg group leaves out only what it names', () {
      Set<String> excluded(AvoidGroup g) => MealPlanner(
            profile: Profile(members: [_adult], diet: DietType.nonveg,
                dayRules: [
                  DayRule(memberIds: const {'a'}, weekdays: const {0}, groups: {g}),
                ]),
            recipes: data.recipes,
            ingredients: data.ingredients,
          ).excludedOn(0);

      expect(excluded(AvoidGroup.chicken),
          {'chicken_breast', 'chicken_curry_cut'});
      expect(excluded(AvoidGroup.fish), {'fish_rohu'});
      expect(excluded(AvoidGroup.egg), {'egg'});
      expect(excluded(AvoidGroup.meat),
          {'chicken_breast', 'chicken_curry_cut'});
      expect(excluded(AvoidGroup.nonVeg),
          {'chicken_breast', 'chicken_curry_cut', 'fish_rohu', 'egg'});
    });

    test('search finds foods by either name', () {
      final palak = data.ingredients['palak']!;
      expect(matchesSearch(palak, 'spin'), isTrue);
      expect(matchesSearch(palak, 'PALAK'), isTrue);
      expect(matchesSearch(palak, 'paneer'), isFalse);
      expect(matchesSearch(data.ingredients['kabuli_chana']!, 'chickpea'),
          isTrue);
      expect(matchesSearch(palak, '  '), isTrue);
    });

    test('groups are found by name, spelling slips and Hindi words', () {
      List<AvoidGroup> find(String q) =>
          AvoidGroup.values.where((g) => g.matchesSearch(q)).toList();
      expect(find('dairy'), [AvoidGroup.dairy]);
      expect(find('Diary'), [AvoidGroup.dairy]);
      expect(find('doodh'), [AvoidGroup.dairy]);
      expect(find('non-veg'), [AvoidGroup.nonVeg]);
      expect(find('non veg'), [AvoidGroup.nonVeg]);
      expect(find('dal'), [AvoidGroup.pulses]);
      expect(find('vrat'), [AvoidGroup.pulses, AvoidGroup.grains]);
      expect(find('pyaz'), [AvoidGroup.onionGarlic]);
      expect(find('meat'), containsAll([AvoidGroup.nonVeg, AvoidGroup.meat]));
      expect(find('zzz'), isEmpty);
    });

    test('new groups cover what their names say', () {
      Set<String> covered(AvoidGroup g) => {
            for (final i in data.ingredients.values)
              if (g.covers(i)) i.id,
          };
      expect(covered(AvoidGroup.dairy),
          {'milk', 'curd', 'paneer', 'butter', 'ghee', 'hung_curd'});
      expect(covered(AvoidGroup.pulses), containsAll(['toor_dal', 'rajma', 'besan']));
      expect(covered(AvoidGroup.grains), containsAll(['atta', 'rice_raw', 'ragi']));
      expect(covered(AvoidGroup.grains), isNot(contains('besan')));
      expect(covered(AvoidGroup.nuts), {'peanuts', 'almonds', 'til'});
    });

    test('a wider group makes the narrower ones inside it redundant', () {
      final foods = data.ingredients.values;
      expect(AvoidGroup.chicken.isImpliedBy({AvoidGroup.nonVeg}, foods), isTrue);
      expect(AvoidGroup.chicken.isImpliedBy({AvoidGroup.meat}, foods), isTrue);
      expect(AvoidGroup.riceWheat.isImpliedBy({AvoidGroup.grains}, foods), isTrue);
      expect(AvoidGroup.grains.isImpliedBy({AvoidGroup.riceWheat}, foods), isFalse);
      expect(AvoidGroup.nonVeg.isImpliedBy({AvoidGroup.meat, AvoidGroup.fish}, foods),
          isFalse);
      expect(
          AvoidGroup.nonVeg.isImpliedBy(
              {AvoidGroup.meat, AvoidGroup.fish, AvoidGroup.egg}, foods),
          isTrue);
    });

    test('a no-non-veg day means no eggs to an eggetarian', () {
      const rule = DayRule(
          memberIds: {'a'}, weekdays: {1}, groups: {AvoidGroup.nonVeg});
      expect(rule.forDiet(DietType.egg).groups, {AvoidGroup.egg});
      expect(rule.forDiet(DietType.nonveg).groups, {AvoidGroup.nonVeg});
      expect(rule.forDiet(DietType.veg).groups, isEmpty);
      expect(AvoidGroup.nonVeg.relevantTo(DietType.egg), isFalse);
      expect(NutrientRole.protein.whyFor(DietType.veg), isNot(contains('meat')));
      expect(NutrientRole.protein.whyFor(DietType.veg), isNot(contains('egg')));
      expect(NutrientRole.protein.whyFor(DietType.nonveg), contains('meat'));
    });

    test('a non-veg household is served meat or fish, except on its no-meat day',
        () {
      for (final rules in [
        <DayRule>[],
        [
          const DayRule(
              memberIds: {'a'}, weekdays: {1}, groups: {AvoidGroup.nonVeg}),
        ],
      ]) {
        final p = Profile(
            members: _family, diet: DietType.nonveg, dayRules: rules);
        for (var seed = 0; seed < 3; seed++) {
          final days = plan(p, seed: seed).days;
          bool meaty(DayPlan d) => d.meals
              .expand((m) => m.components)
              .any((c) => c.recipe.diet == DietType.nonveg);
          expect(days.where(meaty).length, greaterThanOrEqualTo(2),
              reason: 'seed $seed, ${rules.length} rules');
          if (rules.isNotEmpty) {
            expect(days.where((d) => d.weekday == 1).any(meaty), isFalse);
          }
        }
      }
    });

    test('an eggetarian household has eggs most days', () {
      final p = Profile(members: _family, diet: DietType.egg);
      final days = plan(p).days.where((d) => d.meals
          .expand((m) => m.components)
          .any((c) => c.recipe.diet == DietType.egg));
      expect(days.length, greaterThanOrEqualTo(4));
    });

    test('rebalancing keeps the diet-dish weight', () {
      const w = ScoreWeights(dietDish: 1.0);
      expect(w.copyWith(protein: 5).dietDish, 1.0);
    });

    test('rules follow the weekday, whatever day the week starts on', () {
      final p = Profile(members: [_adult], diet: DietType.veg, dayRules: [
        const DayRule(
          memberIds: {'a'},
          weekdays: {3},
          groups: {AvoidGroup.onionGarlic},
        ),
      ]);
      // Starting on a Thursday, day 0 is the observance.
      final week = plan(p, startWeekday: 3);
      expect(week.days.first.dayName, 'Thursday');
      expect(idsOn(week.days.first).intersection({'onion', 'garlic'}), isEmpty);
    });

    test('every single observance, on every day, still fills every meal', () {
      for (final diet in DietType.values) {
        for (final g in AvoidGroup.values.where((g) => g.relevantTo(diet))) {
          final p = Profile(members: [_adult], diet: diet, dayRules: [
            DayRule(
              memberIds: const {'a'},
              weekdays: const {0, 1, 2, 3, 4, 5, 6},
              groups: {g},
            ),
          ]);
          final week = plan(p, seed: 5);
          for (final d in week.days) {
            expect(d.meals.length, 4, reason: '${diet.name} ${g.name} ${d.dayName}');
            for (final ing in idsOn(d)) {
              expect(g.covers(data.ingredients[ing]!), isFalse,
                  reason: '${g.name} served on ${d.dayName}: $ing');
            }
            for (final t in [MealType.lunch, MealType.dinner]) {
              expect(
                  d.mealOf(t)!.components.map((c) => c.recipe.role),
                  contains(RecipeRole.main),
                  reason: '${diet.name} ${g.name} ${d.dayName} ${t.name}');
            }
          }
        }
      }
    });

    test('individually named foods are left out on their day', () {
      final p = Profile(members: [_adult], diet: DietType.veg, dayRules: [
        const DayRule(
            memberIds: {'a'}, weekdays: {0, 1, 2, 3, 4, 5, 6},
            ingredients: {'paneer', 'tomato'}),
      ]);
      for (final d in plan(p).days) {
        expect(idsOn(d).intersection({'paneer', 'tomato'}), isEmpty);
      }
    });

    test('a rule survives a round trip through storage', () {
      final p = Profile(members: [_adult], diet: DietType.egg, dayRules: [
        const DayRule(
          memberIds: {'a'},
          weekdays: {1},
          groups: {AvoidGroup.egg},
          ingredients: {'onion'},
        ),
      ], shopping: ShoppingRhythm.frequent);
      final back = Profile.fromJson(p.toJson());
      expect(back.dayRules.single.groups, {AvoidGroup.egg});
      expect(back.dayRules.single.ingredients, {'onion'});
      expect(back.dayRules.single.weekdays, {1});
      expect(back.shopping, ShoppingRhythm.frequent);
    });
  });

  group('shelf life', () {
    StockLedger replay(WeekPlan w, Profile p) => StockLedger.replay(
        plan: w, ingredients: data.ingredients, profile: p);

    test('perishables are bought on a usual shop and cooked while still good',
        () {
      for (final rhythm in ShoppingRhythm.values) {
        final p = Profile(members: _family, diet: DietType.veg, shopping: rhythm);
        final w = plan(p);
        final ledger = replay(w, p);
        final byDay = w.ingredientsByDay();
        for (final pur in ledger.purchases) {
          final ing = data.ingredients[pur.ingredientId]!;
          if (!pur.topUp) {
            expect(rhythm.tripDays, contains(pur.day),
                reason: '${ing.id} bought on day ${pur.day}');
          }
          // Nothing from this purchase is cooked after it has gone off.
          for (var d = ing.goodUntil(pur.day) + 1; d < 7; d++) {
            final later = ledger.purchases.where((q) =>
                q.ingredientId == ing.id &&
                q.day <= d &&
                ing.goodUntil(q.day) >= d);
            if ((byDay[d][ing.id] ?? 0) > 0) {
              expect(later, isNotEmpty,
                  reason: '${ing.id} cooked on day $d but nothing fresh bought');
            }
          }
        }
      }
    });

    test('a family shopping twice a week wastes almost nothing', () {
      var waste = 0.0;
      for (var seed = 0; seed < 5; seed++) {
        final p = Profile(members: _family, diet: DietType.veg);
        waste += replay(plan(p, seed: seed), p).wasteScore;
      }
      // Measured in packs: under half a pack of anything, across a week.
      expect(waste / 5, lessThan(0.5));
    });

    test('the planner wastes far less than ignoring shelf life would', () {
      final p = Profile(members: [_adult], diet: DietType.veg);
      final careless = MealPlanner(
        profile: p,
        recipes: data.recipes,
        ingredients: data.ingredients,
        weights: const ScoreWeights(useStock: 0, waste: 0, topUp: 0),
      ).generate(seed: 4);
      final careful = plan(p, seed: 4);
      expect(replay(careful, p).wasteScore,
          lessThan(replay(careless, p).wasteScore * 0.4));
    });

    test('shopping trips add up to what the week cooks', () {
      final p = Profile(members: _family, diet: DietType.veg);
      final w = plan(p);
      final list = buildShoppingList(
          plan: w, ingredients: data.ingredients, profile: p);
      final used = <String, double>{};
      for (final t in list.trips) {
        for (final i in t.items) {
          used[i.ingredient.id] = (used[i.ingredient.id] ?? 0) + i.neededQty;
          expect(i.buyQty, greaterThanOrEqualTo(i.neededQty - 1e-6));
        }
      }
      w.ingredientTotals().forEach((id, q) {
        final ing = data.ingredients[id]!;
        if (ing.pantryStaple || ing.dailyFresh) return;
        expect(used[id], closeTo(q, 1e-6), reason: id);
      });
      expect(list.trips.first.day, 0);
      expect(list.trips.map((t) => t.day).toSet(),
          everyElement(isIn(ShoppingRhythm.twice.tripDays)));
    });

    test('milk is bought daily, not stocked', () {
      final p = Profile(members: _family, diet: DietType.veg);
      final w = plan(p);
      final list = buildShoppingList(
          plan: w, ingredients: data.ingredients, profile: p);
      final inTrips = {
        for (final t in list.trips)
          for (final i in t.items) i.ingredient.id
      };
      expect(inTrips, isNot(contains('milk')));
      if ((w.ingredientTotals()['milk'] ?? 0) > 0) {
        expect(list.daily.map((d) => d.ingredient.id), contains('milk'));
      }
    });
  });

  group('adapting to what was eaten', () {
    Profile p() => Profile(members: _family, diet: DietType.veg);

    DayFeedback skippedAll(DayPlan d) =>
        DayFeedback(d.dayIndex, {for (final m in d.meals) m.type: MealOutcome.skipped});

    test('a day that went to plan leaves the week alone', () {
      final w = plan(p());
      final fb = DayFeedback(0, {
        for (final m in w.days[0].meals) m.type: MealOutcome.asPlanned
      });
      final a = adaptWeek(
        progress: WeekProgress(plan: w, feedback: {0: fb}),
        throughDay: 0,
        latest: fb,
        profile: p(),
        recipes: data.recipes,
        ingredients: data.ingredients,
      );
      expect(a.replanned, isFalse);
      expect(a.progress.plan.toJson(), equals(w.toJson()));
      expect(a.progress.frozenThrough, 0);
      expect(a.progress.bought.every((b) => b.day == 0), isTrue);
    });

    test('a missed day is made up over the rest of the week', () {
      final w = plan(p());
      final fb = skippedAll(w.days[1]);
      final a = adaptWeek(
        progress: WeekProgress(plan: w, feedback: {1: fb}),
        throughDay: 1,
        latest: fb,
        profile: p(),
        recipes: data.recipes,
        ingredients: data.ingredients,
      );
      expect(a.replanned, isTrue);
      expect(a.fromDay, 2);
      expect(a.dayAdjust.protein, greaterThan(0));

      // Days already lived through are kept exactly.
      for (var d = 0; d < 2; d++) {
        expect(a.progress.plan.toJson()['days'][d], w.toJson()['days'][d]);
      }
      double proteinFrom(WeekPlan x) => x.days
          .skip(2)
          .fold(0.0, (s, d) => s + d.nutrients(data.ingredients).protein);
      expect(proteinFrom(a.progress.plan), greaterThan(proteinFrom(w)));
    });

    test('shops already made stay as they were listed', () {
      final w = plan(p());
      final before = buildShoppingList(
          plan: w, ingredients: data.ingredients, profile: p());
      final fb = skippedAll(w.days[0]);
      final a = adaptWeek(
        progress: WeekProgress(plan: w, feedback: {0: fb}),
        throughDay: 0,
        latest: fb,
        profile: p(),
        recipes: data.recipes,
        ingredients: data.ingredients,
      );
      final after = buildShoppingList(
        plan: a.progress.plan,
        ingredients: data.ingredients,
        profile: p(),
        stock: a.progress.ledger(data.ingredients, p()),
      );
      Map<String, double> day0(ShoppingList l) => {
            for (final i in l.trips.firstWhere((t) => t.day == 0).items)
              i.ingredient.id: i.buyQty
          };
      expect(day0(after), equals(day0(before)));
    });

    test('food bought for skipped meals gets cooked instead of wasted', () {
      var replannedWaste = 0.0;
      var ignoredWaste = 0.0;
      for (var seed = 0; seed < 4; seed++) {
        final w = plan(p(), seed: seed);
        final fb = skippedAll(w.days[0]);
        final a = adaptWeek(
          progress: WeekProgress(plan: w, feedback: {0: fb}),
          throughDay: 0,
          latest: fb,
          profile: p(),
          recipes: data.recipes,
          ingredients: data.ingredients,
        );
        replannedWaste +=
            a.progress.ledger(data.ingredients, p()).wasteScore;
        // The same day skipped, but the rest of the week carried on as if
        // nothing had happened.
        ignoredWaste += WeekProgress(
          plan: w,
          feedback: {0: fb},
          bought: a.progress.bought,
          frozenThrough: 0,
        ).ledger(data.ingredients, p()).wasteScore;
      }
      expect(replannedWaste, lessThan(ignoredWaste));
    });

    test('a plan and its feedback survive a round trip through storage', () {
      final w = plan(p(), startWeekday: 4);
      final byId = {for (final r in data.recipes) r.id: r};
      final back = WeekPlan.fromJson(w.toJson(), byId)!;
      expect(back.toJson(), equals(w.toJson()));
      expect(back.days.first.dayName, 'Friday');

      const fb = DayFeedback(2, {
        MealType.lunch: MealOutcome.half,
        MealType.dinner: MealOutcome.other,
      });
      final fbBack = DayFeedback.fromJson(fb.toJson());
      expect(fbBack.outcomeOf(MealType.lunch), MealOutcome.half);
      expect(fbBack.outcomeOf(MealType.breakfast), MealOutcome.asPlanned);
    });

    test('eating out keeps the energy but not the protein', () {
      const planned = Nutrients(kcal: 600, protein: 30, iron: 4);
      final eaten = MealOutcome.other.eaten(planned);
      expect(eaten.kcal, 600);
      expect(eaten.protein, 15);
      expect(MealOutcome.other.ingredientShare, 0);
    });
  });
}
