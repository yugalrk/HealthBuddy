import 'package:flutter_test/flutter_test.dart';
import 'package:healthbuddy/engine/day_score.dart';
import 'package:healthbuddy/models/food.dart';
import 'package:healthbuddy/models/plan.dart';

const _target = Nutrients(
  kcal: 2000,
  protein: 60,
  fat: 65,
  carb: 280,
  fibre: 30,
  iron: 17,
  calcium: 1000,
);

DayScore _score(Nutrients eaten, {int junk = 0, DateTime? date}) => scoreDay(
      date: date ?? DateTime(2026, 9, 21),
      eaten: eaten,
      target: _target,
      junkSnacks: junk,
    );

Nutrients _with({
  double kcal = 1,
  double protein = 1,
  double fibre = 1,
  double iron = 1,
  double calcium = 1,
}) =>
    Nutrients(
      kcal: _target.kcal * kcal,
      protein: _target.protein * protein,
      fat: _target.fat,
      carb: _target.carb,
      fibre: _target.fibre * fibre,
      iron: _target.iron * iron,
      calcium: _target.calcium * calcium,
    );

void main() {
  group('day score', () {
    test('every goal met, no junk, scores 100', () {
      final s = _score(_target);
      expect(s.score, 100);
      expect(s.isProperDay, isTrue);
      expect(s.misses, isEmpty);
    });

    test('small misses inside the tolerances still score 100', () {
      final s = _score(_with(kcal: 1.08, protein: 0.96, fibre: 0.92));
      expect(s.score, 100);
    });

    test('going over on protein or micronutrients costs nothing', () {
      expect(_score(_with(protein: 1.8, iron: 2, calcium: 1.5)).score, 100);
    });

    test('missing protein costs up to 30 points', () {
      final short = _score(_with(protein: 0.7));
      expect(short.score, 83); // 30 * (0.2 / 0.45) = 13.3 kept of 30
      expect(short.misses.first, startsWith('Protein short — 70%'));
      expect(_score(_with(protein: 0.4)).score, 70);
    });

    test('going over on calories costs more than falling short', () {
      final over = _score(_with(kcal: 1.25));
      final under = _score(_with(kcal: 0.75));
      expect(over.score, 85);
      expect(under.score, lessThan(100));
      expect(over.score, lessThan(under.score));
      expect(over.misses.first, 'Calories over — 25% above your target');
      expect(_score(_with(kcal: 1.5)).energyPoints, 0);
    });

    test('junk snacks cost points, and their calories count too', () {
      final one = _score(_target, junk: 1);
      final two = _score(_target, junk: 2);
      // One snack: -10 for junk; +12.5% calories is just past the tolerance.
      expect(one.score, 88);
      // Two: -20 for junk, and +25% calories costs 15 more.
      expect(two.score, 65);
      expect(two.isProperDay, isFalse);
      expect(two.misses, contains('2 junk snacks'));
      expect(_score(_target, junk: 5).junkPoints, 0);
    });

    test('a day of nothing scores low, never below zero', () {
      final s = _score(Nutrients.zero, junk: 4);
      expect(s.score, greaterThanOrEqualTo(0));
      expect(s.score, lessThan(20));
    });

    test('misses are listed most costly first', () {
      final s = _score(_with(protein: 0.6, iron: 0.8), junk: 1);
      expect(s.misses.first, startsWith('Protein short'));
      expect(s.misses.last, startsWith('Iron short'));
    });

    test('survives a round trip through JSON', () {
      final s = _score(_with(protein: 0.8, kcal: 1.2), junk: 2);
      final back = DayScore.fromJson(s.toJson());
      expect(back.score, s.score);
      expect(back.date, s.date);
      expect(back.junkSnacks, 2);
    });
  });

  group('score log', () {
    DayScore on(int day, {double protein = 1}) =>
        _score(_with(protein: protein), date: DateTime(2026, 9, day));

    test('keeps one score per date, the latest', () {
      final log = ScoreLog()
        ..put(on(21, protein: 0.5))
        ..put(on(21));
      expect(log.days, hasLength(1));
      expect(log.days.single.score, 100);
    });

    test('counts a streak of proper days back from the latest', () {
      final log = ScoreLog()
        ..put(on(17))
        ..put(on(18, protein: 0.5)) // an off day breaks it
        ..put(on(19))
        ..put(on(20))
        ..put(on(21));
      expect(log.properStreak, 3);
      log.put(on(23)); // a gap breaks it too
      expect(log.properStreak, 1);
    });

    test('lists the days in a window and forgets very old ones', () {
      final log = ScoreLog();
      for (var d = 1; d <= 30; d++) {
        log.put(on(d));
      }
      expect(log.lastDays(7, DateTime(2026, 9, 30)), hasLength(7));
      log.put(_score(_target, date: DateTime(2027, 1, 30)));
      expect(log.days.first.date.isAfter(DateTime(2026, 10, 31)), isTrue);
      final back = ScoreLog.fromJson(log.toJson());
      expect(back.days.length, log.days.length);
    });
  });

  test('check-in junk snacks are saved, and old check-ins read as none', () {
    const fb = DayFeedback(2, {MealType.lunch: MealOutcome.half}, junkSnacks: 2);
    expect(DayFeedback.fromJson(fb.toJson()).junkSnacks, 2);
    expect(
        DayFeedback.fromJson({
          'day': 1,
          'meals': {'lunch': 'asPlanned'}
        }).junkSnacks,
        0);
  });
}
