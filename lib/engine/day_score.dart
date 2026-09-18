/// How well a day met the goals, as a score out of 100.
///
/// The evening check-in tells the app what was actually eaten. From that, and
/// how many junk snacks were had, each day gets a score: 100 when every goal
/// was met, less for missing protein, going over (or well under) on
/// calories, falling short on fibre, iron or calcium, and for junk food.
///
/// Points, out of 100:
///
/// * **Protein — 30.** Full at 95% of target or more; none at half.
/// * **Calories — 30.** Full within 10% either way. Going over costs faster
///   than falling short: none at 40% over, or at 50% under.
/// * **Fibre, iron, calcium — 20** (7, 7 and 6). Full at 90% or more; none
///   at 40%.
/// * **No junk — 20.** Each junk snack costs 10, and adds its calories to
///   the day as well.
///
/// The score is personal: [scoreDay] takes what one person ate against that
/// person's own targets.
library;

import 'dart:math' as math;

import '../models/food.dart';

/// A day at or above this counts as a proper day.
const int properDayScore = 85;

/// What one junk snack — a samosa, a packet of chips, sweets, a soft drink —
/// adds, roughly: plenty of energy and fat, little of anything else.
const junkSnack = Nutrients(
  kcal: 250,
  protein: 3,
  fat: 13,
  carb: 30,
  fibre: 1,
  iron: 0.5,
  calcium: 20,
);

/// Points each part of the score is worth.
class ScorePoints {
  static const protein = 30.0;
  static const energy = 30.0;
  static const fibre = 7.0;
  static const iron = 7.0;
  static const calcium = 6.0;
  static const junk = 20.0;
  static const perJunkSnack = 10.0;
}

/// One day's score, and what it was made of.
class DayScore {
  const DayScore({
    required this.date,
    required this.protein,
    required this.energy,
    required this.fibre,
    required this.iron,
    required this.calcium,
    required this.junkSnacks,
  });

  /// The day, at midnight local time.
  final DateTime date;

  /// What was eaten as a share of target: 1.0 is exactly on target.
  final double protein;
  final double energy;
  final double fibre;
  final double iron;
  final double calcium;
  final int junkSnacks;

  double get proteinPoints =>
      _upTo(protein, full: 0.95, zero: 0.5) * ScorePoints.protein;

  double get energyPoints {
    final dev = energy - 1;
    final part = dev.abs() <= 0.10
        ? 1.0
        : dev > 0
            ? 1 - (dev - 0.10) / 0.30
            : 1 - (-dev - 0.10) / 0.40;
    return part.clamp(0.0, 1.0) * ScorePoints.energy;
  }

  double get microPoints =>
      _upTo(fibre, full: 0.9, zero: 0.4) * ScorePoints.fibre +
      _upTo(iron, full: 0.9, zero: 0.4) * ScorePoints.iron +
      _upTo(calcium, full: 0.9, zero: 0.4) * ScorePoints.calcium;

  double get junkPoints => math.max(
      0.0, ScorePoints.junk - ScorePoints.perJunkSnack * junkSnacks);

  /// Out of 100.
  int get score =>
      (proteinPoints + energyPoints + microPoints + junkPoints).round();

  bool get isProperDay => score >= properDayScore;

  /// What cost points, most costly first, in plain words. Empty for a
  /// perfect day.
  List<String> get misses {
    final out = <(double, String)>[];
    void add(double lost, String why) {
      if (lost >= 0.5) out.add((lost, why));
    }

    String pct(double r) => '${(r * 100).round()}%';
    add(ScorePoints.protein - proteinPoints,
        'Protein short — ${pct(protein)} of your target');
    final e = ScorePoints.energy - energyPoints;
    add(e,
        energy > 1
            ? 'Calories over — ${pct(energy - 1)} above your target'
            : 'Calories low — ${pct(1 - energy)} under your target');
    add(ScorePoints.fibre * (1 - _upTo(fibre, full: 0.9, zero: 0.4)),
        'Fibre short — ${pct(fibre)} of your target');
    add(ScorePoints.iron * (1 - _upTo(iron, full: 0.9, zero: 0.4)),
        'Iron short — ${pct(iron)} of your target');
    add(ScorePoints.calcium * (1 - _upTo(calcium, full: 0.9, zero: 0.4)),
        'Calcium short — ${pct(calcium)} of your target');
    add(ScorePoints.junk - junkPoints,
        '$junkSnacks junk ${junkSnacks == 1 ? 'snack' : 'snacks'}');
    out.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final m in out) m.$2];
  }

  Map<String, dynamic> toJson() => {
        'date': _ymd(date),
        'protein': protein,
        'energy': energy,
        'fibre': fibre,
        'iron': iron,
        'calcium': calcium,
        'junk': junkSnacks,
      };

  static DayScore fromJson(Map<String, dynamic> j) => DayScore(
        date: DateTime.parse(j['date'] as String),
        protein: (j['protein'] as num).toDouble(),
        energy: (j['energy'] as num).toDouble(),
        fibre: (j['fibre'] as num).toDouble(),
        iron: (j['iron'] as num).toDouble(),
        calcium: (j['calcium'] as num).toDouble(),
        junkSnacks: j['junk'] as int? ?? 0,
      );
}

/// Score a day: [eaten] by one person against [target], their own daily
/// targets, with [junkSnacks] junk snacks on top.
DayScore scoreDay({
  required DateTime date,
  required Nutrients eaten,
  required Nutrients target,
  int junkSnacks = 0,
}) {
  final total = eaten + junkSnack * junkSnacks.toDouble();
  double r(double got, double want) => want <= 0 ? 1.0 : got / want;
  return DayScore(
    date: DateTime(date.year, date.month, date.day),
    protein: r(total.protein, target.protein),
    energy: r(total.kcal, target.kcal),
    fibre: r(total.fibre, target.fibre),
    iron: r(total.iron, target.iron),
    calcium: r(total.calcium, target.calcium),
    junkSnacks: junkSnacks,
  );
}

/// Every scored day, newest last, one per date.
class ScoreLog {
  ScoreLog([Iterable<DayScore> days = const []]) {
    for (final d in days) {
      _byDate[_ymd(d.date)] = d;
    }
  }

  /// Days kept. A quarter is plenty to see a trend, and keeps storage small.
  static const keepDays = 90;

  final Map<String, DayScore> _byDate = {};

  List<DayScore> get days =>
      _byDate.values.toList()..sort((a, b) => a.date.compareTo(b.date));

  bool get isEmpty => _byDate.isEmpty;

  DayScore? on(DateTime date) => _byDate[_ymd(date)];

  /// Add or replace the score for [s]'s date, and drop anything older than
  /// [keepDays] before the newest day.
  void put(DayScore s) {
    _byDate[_ymd(s.date)] = s;
    final newest = days.last.date;
    _byDate.removeWhere(
        (_, d) => newest.difference(d.date).inDays >= keepDays);
  }

  /// Scored days among the [n] days ending on [until].
  List<DayScore> lastDays(int n, DateTime until) {
    final end = DateTime(until.year, until.month, until.day);
    return [
      for (final d in days)
        if (!d.date.isAfter(end) && end.difference(d.date).inDays < n) d
    ];
  }

  /// Consecutive proper days, counting back from the most recent scored day.
  int get properStreak {
    var n = 0;
    DateTime? expect;
    for (final d in days.reversed) {
      if (expect != null && d.date != expect) break;
      if (!d.isProperDay) break;
      n++;
      // The calendar day before, not 24 hours before: safe across DST.
      expect = DateTime(d.date.year, d.date.month, d.date.day - 1);
    }
    return n;
  }

  List<Map<String, dynamic>> toJson() => [for (final d in days) d.toJson()];

  static ScoreLog fromJson(List<dynamic> j) => ScoreLog(
      [for (final d in j) DayScore.fromJson(d as Map<String, dynamic>)]);
}

double _upTo(double r, {required double full, required double zero}) =>
    ((r - zero) / (full - zero)).clamp(0.0, 1.0).toDouble();

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';
