/// Nutritional target computation.
///
/// All reference values are ICMR-NIN 2020 (*Nutrient Requirements for Indians*,
/// https://www.nin.res.in/rdabook/brief_note.pdf) unless explicitly noted.
/// See docs/NUTRITION_SOURCES.md.
library;

import 'dart:math' as math;

import '../models/food.dart';
import '../models/profile.dart';

/// Mifflin-St Jeor basal metabolic rate, kcal/day.
///
/// Chosen over Harris-Benedict because it is the better-validated predictive
/// equation for modern populations.
double mifflinStJeorBmr({
  required Sex sex,
  required double weightKg,
  required double heightCm,
  required int age,
}) {
  final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
  return sex == Sex.male ? base + 5 : base - 161;
}

/// Total daily energy expenditure before any goal adjustment.
double tdee(HouseholdMember m) =>
    mifflinStJeorBmr(
      sex: m.sex,
      weightKg: m.weightKg,
      heightCm: m.heightCm,
      age: m.age,
    ) *
    m.activity.factor;

/// Baseline protein requirement by goal, g per kg body weight per day.
///
/// [Goal.maintain] uses the ICMR-NIN 2020 RDA of 0.83 g/kg/day. The raised
/// figures for fat loss and muscle gain come from sports-nutrition consensus,
/// **not** from ICMR-NIN, and are labelled as such in the app.
const Map<Goal, double> _proteinBaseByGoal = {
  Goal.maintain: 0.83,
  Goal.lose: 1.2,
  Goal.gain: 1.6,
};

/// Cereal-dominant (vegetarian) equivalents of [_proteinBaseByGoal].
///
/// The maintenance row is ICMR-NIN's own stated figure of 1 g/kg/day for
/// cereal-based diets, not a computed one. The other two rows are the mixed-diet
/// baselines scaled by [cerealDietProteinFactor], which is the 1.2 ratio implied
/// by ICMR-NIN's 0.83 -> 1.0 adjustment.
const Map<Goal, double> _proteinVegByGoal = {
  Goal.maintain: 1.0,
  Goal.lose: 1.44,
  Goal.gain: 1.92,
};

/// Quality/digestibility uplift for cereal-dominant (vegetarian) Indian diets.
///
/// ICMR-NIN 2020 states that for people on a cereal-based diet with lower
/// quality protein the requirement is 1 g/kg/day rather than 0.83 — exactly a
/// factor of 1.2. We apply that same factor to the fat-loss and muscle-gain
/// baselines, which is why a vegetarian building muscle is targeted higher than
/// a non-vegetarian with the same goal.
const double cerealDietProteinFactor = 1.2;

/// Safety ceiling. Well below the ~2.5 g/kg at which intake becomes a concern
/// for healthy adults, but high enough not to bind for normal goals.
const double maxProteinPerKg = 2.0;

double proteinPerKg({required DietType diet, required Goal goal}) {
  final v = diet == DietType.veg
      ? _proteinVegByGoal[goal]!
      : _proteinBaseByGoal[goal]!;
  return math.min(v, maxProteinPerKg);
}

/// ICMR-NIN 2020 iron RDA, mg/day.
///
/// The high figure for menstruating women reflects both menstrual losses and
/// the low (~8%) bioavailability of iron from typical Indian diets. We step
/// down to the male figure at 50 as an approximation of menopause; ICMR-NIN
/// gives 19 mg for the 60+ group.
double _ironRda(HouseholdMember m) {
  if (m.sex == Sex.male) return 19;
  return m.age >= 50 ? 19 : 29;
}

/// ICMR-NIN 2020 calcium RDA, mg/day — 1000 mg for adult men and women alike.
double _calciumRda(HouseholdMember m) => m.age >= 60 ? 1200 : 1000;

/// Dietary fibre. ICMR-NIN's brief note does not give a single adult RDA, so
/// this uses the widely used 30 g per 2000 kcal density heuristic.
double fibreTargetFor(double kcal) => kcal / 2000 * 30;

/// Minimum share of energy left for carbohydrate after protein and fat.
const double _minCarbEnergyShare = 0.10;

/// Fat as a share of energy. 25% is mid-range of the ICMR-NIN 20–30% band.
const double _fatEnergyShare = 0.25;
const double _minFatEnergyShare = 0.20;

/// Daily nutrient targets for a single person.
///
/// Energy is floored at 1.1 × BMR so an aggressive weight-loss goal can never
/// drive the plan below a safe intake.
Nutrients targetsForMember(HouseholdMember m, DietType diet) {
  final bmr = mifflinStJeorBmr(
    sex: m.sex,
    weightKg: m.weightKg,
    heightCm: m.heightCm,
    age: m.age,
  );
  final floor = bmr * 1.1;
  var kcal = bmr * m.activity.factor + m.goal.kcalDelta;
  if (kcal < floor) kcal = floor;

  final proteinG = m.weightKg * proteinPerKg(diet: diet, goal: m.goal);
  final proteinKcal = proteinG * 4;

  var fatKcal = kcal * _fatEnergyShare;
  // Keep at least [_minCarbEnergyShare] of energy for carbohydrate; if protein
  // is large enough to squeeze it, take the room out of fat first, but never
  // below [_minFatEnergyShare] of energy.
  final maxFatKcal = kcal - proteinKcal - kcal * _minCarbEnergyShare;
  if (fatKcal > maxFatKcal) {
    fatKcal = math.max(kcal * _minFatEnergyShare, maxFatKcal);
  }
  final fatG = fatKcal / 9;

  final carbKcal = math.max(0.0, kcal - proteinKcal - fatKcal);

  return Nutrients(
    kcal: kcal,
    protein: proteinG,
    fat: fatG,
    carb: carbKcal / 4,
    fibre: fibreTargetFor(kcal),
    iron: _ironRda(m),
    calcium: _calciumRda(m),
  );
}

/// Combined daily targets for the whole household.
///
/// Meals are cooked once for everyone, so the planner works against this
/// aggregate rather than against each member individually.
Nutrients householdDailyTargets(Profile p) => Nutrients.sum(
      p.members.map((m) => targetsForMember(m, p.diet)),
    );

Nutrients householdWeeklyTargets(Profile p) => householdDailyTargets(p) * 7;

/// Reference adult energy intake used to convert household energy needs into a
/// number of recipe servings to cook.
const double referenceServingKcal = 2000;

/// How many "standard portions" the household eats per day.
///
/// A recipe authored for 4 servings feeds 4 reference adults; a household of
/// two adults and a child might be 2.4 portions, so that recipe is scaled by
/// 2.4/4. This is what makes the shopping list track household size.
double householdPortions(Profile p) =>
    householdDailyTargets(p).kcal / referenceServingKcal;

/// A nutrient the app reports on, with the reasoning behind its figure.
///
/// Kept next to the calculations rather than in the UI so the explanation and
/// the number can never drift apart.
class NutrientGuide {
  const NutrientGuide({
    required this.label,
    required this.unit,
    required this.read,
    required this.why,
    required this.basis,
  });

  final String label;
  final String unit;

  /// Pulls this nutrient out of a [Nutrients] vector.
  final double Function(Nutrients) read;

  /// What it does, in one line.
  final String why;

  /// Where the recommended figure comes from.
  final String basis;
}

/// The nutrients the app gives a recommended intake for, in reporting order.
const List<NutrientGuide> nutrientGuides = [
  NutrientGuide(
    label: 'Energy',
    unit: 'kcal',
    read: _readKcal,
    why: 'Total daily fuel. Too little and you lose muscle along with fat; '
        'too much and the surplus is stored.',
    basis: 'Mifflin-St Jeor equation from your height, weight, age and sex, '
        'scaled by activity, then adjusted for your goal.',
  ),
  NutrientGuide(
    label: 'Protein',
    unit: 'g',
    read: _readProtein,
    why: 'Builds and repairs muscle and keeps you full. This is the target '
        'most Indian households miss.',
    basis: 'ICMR-NIN 2020: 0.83 g per kg body weight, raised to 1.0 g/kg on a '
        'vegetarian cereal-based diet because its protein is less digestible. '
        'Higher again for muscle gain or fat loss.',
  ),
  NutrientGuide(
    label: 'Fat',
    unit: 'g',
    read: _readFat,
    why: 'Carries fat-soluble vitamins and supplies essential fatty acids.',
    basis: '25% of your energy, the midpoint of the ICMR-NIN 20-30% band.',
  ),
  NutrientGuide(
    label: 'Carbohydrate',
    unit: 'g',
    read: _readCarb,
    why: 'Your main working fuel, mostly from grains, dals and vegetables.',
    basis: 'Whatever energy remains once protein and fat are set.',
  ),
  NutrientGuide(
    label: 'Fibre',
    unit: 'g',
    read: _readFibre,
    why: 'Digestion, blood sugar and cholesterol. Dals and whole grains are '
        'the main sources.',
    basis: '30 g per 2000 kcal — a density heuristic, as ICMR-NIN publishes no '
        'single adult figure.',
  ),
  NutrientGuide(
    label: 'Iron',
    unit: 'mg',
    read: _readIron,
    why: 'Carries oxygen in the blood. Deficiency is common in India, '
        'especially among women.',
    basis: 'ICMR-NIN 2020: 19 mg for men, 29 mg for menstruating women. The '
        'high figure reflects the low absorption of iron from Indian diets.',
  ),
  NutrientGuide(
    label: 'Calcium',
    unit: 'mg',
    read: _readCalcium,
    why: 'Bone strength, and it keeps mattering well past childhood.',
    basis: 'ICMR-NIN 2020: 1000 mg for adults, 1200 mg over 60.',
  ),
];

double _readKcal(Nutrients n) => n.kcal;
double _readProtein(Nutrients n) => n.protein;
double _readFat(Nutrients n) => n.fat;
double _readCarb(Nutrients n) => n.carb;
double _readFibre(Nutrients n) => n.fibre;
double _readIron(Nutrients n) => n.iron;
double _readCalcium(Nutrients n) => n.calcium;

/// Per-member breakdown, for the "why these numbers" screen.
class MemberTargets {
  const MemberTargets(this.member, this.targets, this.proteinGPerKg);
  final HouseholdMember member;
  final Nutrients targets;
  final double proteinGPerKg;
}

List<MemberTargets> memberBreakdown(Profile p) => [
      for (final m in p.members)
        MemberTargets(
          m,
          targetsForMember(m, p.diet),
          proteinPerKg(diet: p.diet, goal: m.goal),
        ),
    ];
