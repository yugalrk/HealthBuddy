import 'package:flutter_test/flutter_test.dart';
import 'package:healthbuddy/engine/targets.dart';
import 'package:healthbuddy/models/profile.dart';

HouseholdMember member({
  Sex sex = Sex.male,
  double weightKg = 70,
  double heightCm = 175,
  int age = 30,
  ActivityLevel activity = ActivityLevel.moderate,
  Goal goal = Goal.maintain,
}) =>
    HouseholdMember(
      id: 'm1',
      name: 'Test',
      age: age,
      sex: sex,
      weightKg: weightKg,
      heightCm: heightCm,
      activity: activity,
      goal: goal,
      isPrimary: true,
    );

void main() {
  group('Mifflin-St Jeor BMR', () {
    test('male matches hand-computed value', () {
      // 10*70 + 6.25*175 - 5*30 + 5 = 700 + 1093.75 - 150 + 5 = 1648.75
      final bmr = mifflinStJeorBmr(
          sex: Sex.male, weightKg: 70, heightCm: 175, age: 30);
      expect(bmr, closeTo(1648.75, 0.01));
    });

    test('female matches hand-computed value', () {
      // 10*55 + 6.25*160 - 5*30 - 161 = 550 + 1000 - 150 - 161 = 1239
      final bmr = mifflinStJeorBmr(
          sex: Sex.female, weightKg: 55, heightCm: 160, age: 30);
      expect(bmr, closeTo(1239.0, 0.01));
    });

    test('female BMR is below male BMR at identical body measurements', () {
      final m = mifflinStJeorBmr(
          sex: Sex.male, weightKg: 70, heightCm: 175, age: 30);
      final f = mifflinStJeorBmr(
          sex: Sex.female, weightKg: 70, heightCm: 175, age: 30);
      expect(f, lessThan(m));
      expect(m - f, closeTo(166.0, 0.01));
    });
  });

  group('protein targets follow ICMR-NIN 2020', () {
    test('non-vegetarian maintenance uses the 0.83 g/kg RDA', () {
      expect(proteinPerKg(diet: DietType.nonveg, goal: Goal.maintain),
          closeTo(0.83, 1e-9));
    });

    test('vegetarian maintenance is raised to 1.0 g/kg', () {
      // ICMR-NIN: cereal-based diets with lower protein quality need 1 g/kg.
      expect(proteinPerKg(diet: DietType.veg, goal: Goal.maintain),
          closeTo(1.0, 1e-9));
    });

    test('eggetarian is treated as mixed-quality, not cereal-based', () {
      expect(proteinPerKg(diet: DietType.egg, goal: Goal.maintain),
          closeTo(0.83, 1e-9));
    });

    test('muscle gain raises protein above maintenance', () {
      expect(proteinPerKg(diet: DietType.nonveg, goal: Goal.gain),
          greaterThan(proteinPerKg(diet: DietType.nonveg, goal: Goal.maintain)));
    });

    test('vegetarian target exceeds non-vegetarian for the same goal', () {
      for (final g in Goal.values) {
        expect(proteinPerKg(diet: DietType.veg, goal: g),
            greaterThan(proteinPerKg(diet: DietType.nonveg, goal: g)),
            reason: 'goal $g');
      }
    });

    test('never exceeds the safety ceiling', () {
      for (final d in DietType.values) {
        for (final g in Goal.values) {
          expect(proteinPerKg(diet: d, goal: g),
              lessThanOrEqualTo(maxProteinPerKg));
        }
      }
    });
  });

  group('member targets', () {
    test('macros reconcile with total energy', () {
      final t = targetsForMember(member(), DietType.veg);
      final fromMacros = t.protein * 4 + t.fat * 9 + t.carb * 4;
      expect(fromMacros, closeTo(t.kcal, 1.0));
    });

    test('aggressive weight loss is floored at 1.1x BMR', () {
      // A small, sedentary person with a -500 deficit would otherwise be
      // pushed to an unsafe intake.
      final m = member(
        sex: Sex.female,
        weightKg: 45,
        heightCm: 150,
        age: 55,
        activity: ActivityLevel.sedentary,
        goal: Goal.lose,
      );
      final bmr = mifflinStJeorBmr(
          sex: m.sex, weightKg: m.weightKg, heightCm: m.heightCm, age: m.age);
      final t = targetsForMember(m, DietType.veg);
      expect(t.kcal, greaterThanOrEqualTo(bmr * 1.1 - 0.01));
    });

    test('carbohydrate never goes negative even at maximum protein', () {
      final m = member(weightKg: 110, activity: ActivityLevel.sedentary, goal: Goal.lose);
      final t = targetsForMember(m, DietType.veg);
      expect(t.carb, greaterThanOrEqualTo(0));
      expect(t.fat, greaterThan(0));
    });

    test('iron target reflects ICMR-NIN sex and age differences', () {
      final man = targetsForMember(member(sex: Sex.male), DietType.veg);
      final woman = targetsForMember(
          member(sex: Sex.female, weightKg: 55, heightCm: 160), DietType.veg);
      final olderWoman = targetsForMember(
          member(sex: Sex.female, weightKg: 55, heightCm: 160, age: 58),
          DietType.veg);
      expect(man.iron, 19);
      expect(woman.iron, 29);
      expect(olderWoman.iron, 19);
    });

    test('calcium target is the ICMR-NIN 1000 mg adult RDA', () {
      expect(targetsForMember(member(), DietType.veg).calcium, 1000);
    });

    test('higher activity produces a higher energy target', () {
      final low = targetsForMember(
          member(activity: ActivityLevel.sedentary), DietType.veg);
      final high = targetsForMember(
          member(activity: ActivityLevel.active), DietType.veg);
      expect(high.kcal, greaterThan(low.kcal));
    });
  });

  group('household aggregation', () {
    test('targets scale with the number of people', () {
      final one = Profile(members: [member()], diet: DietType.veg);
      final four = Profile(
        members: [
          member(),
          member(sex: Sex.female, weightKg: 55, heightCm: 160),
          HouseholdMember.reference(
              id: 'c1', name: 'Child', age: 10, sex: Sex.male),
          HouseholdMember.reference(
              id: 'c2', name: 'Elder', age: 65, sex: Sex.female),
        ],
        diet: DietType.veg,
      );
      final t1 = householdDailyTargets(one);
      final t4 = householdDailyTargets(four);
      expect(t4.kcal, greaterThan(t1.kcal * 2.5));
      expect(t4.protein, greaterThan(t1.protein * 2.5));
    });

    test('household portions track total energy need', () {
      final p = Profile(members: [member(), member()], diet: DietType.veg);
      final portions = householdPortions(p);
      expect(portions, greaterThan(1.5));
      expect(portions, lessThan(4.0));
    });

    test('weekly targets are exactly seven daily targets', () {
      final p = Profile(members: [member()], diet: DietType.veg);
      expect(householdWeeklyTargets(p).protein,
          closeTo(householdDailyTargets(p).protein * 7, 1e-9));
    });
  });
}
