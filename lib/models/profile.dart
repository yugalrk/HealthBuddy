/// User, household and preference models.
///
/// Nutrition references throughout are ICMR-NIN 2020 (Nutrient Requirements for
/// Indians). See docs/NUTRITION_SOURCES.md for provenance of every figure.
library;

enum Sex { male, female }

/// Physical activity multipliers applied to BMR to reach TDEE.
enum ActivityLevel {
  sedentary(1.2, 'Sedentary', 'Desk job, little or no exercise'),
  light(1.375, 'Lightly active', 'Light exercise 1–3 days a week'),
  moderate(1.55, 'Moderately active', 'Moderate exercise 3–5 days a week'),
  active(1.725, 'Very active', 'Hard exercise 6–7 days a week');

  const ActivityLevel(this.factor, this.label, this.description);
  final double factor;
  final String label;
  final String description;
}

/// Goal drives both the energy delta and the protein target.
enum Goal {
  lose('Lose weight', -500),
  maintain('Stay healthy', 0),
  gain('Build muscle', 350);

  const Goal(this.label, this.kcalDelta);
  final String label;
  final int kcalDelta;
}

/// Ordered by permissiveness: a user set to [nonveg] can eat everything,
/// a user set to [veg] can eat only `veg` recipes.
enum DietType {
  veg('Vegetarian'),
  egg('Eggetarian'),
  nonveg('Non-vegetarian');

  const DietType(this.label);
  final String label;

  /// Whether a recipe tagged [recipeDiet] is acceptable to this user.
  bool admits(DietType recipeDiet) => recipeDiet.index <= index;
}

/// Day names, indexed by weekday with 0 = Monday.
const weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Foods commonly given up on a particular day of the week for religious or
/// cultural reasons — no meat on Tuesdays, no onion or garlic on a fast day.
enum AvoidGroup {
  nonVeg('All non-veg', 'Meat, chicken, fish and eggs',
      ['non-veg', 'nonveg', 'meat', 'mansahari']),
  meat('Meat', 'Chicken, mutton and any other meat',
      ['mutton', 'goat', 'lamb', 'gosht']),
  chicken('Chicken', 'Only chicken', ['murga', 'murgh']),
  fish('Fish & seafood', 'Fish, prawns and other seafood',
      ['seafood', 'prawn', 'machli', 'machhli']),
  egg('Eggs', 'Eggs in any form', ['anda', 'ande']),
  dairy('Dairy', 'Milk, curd, paneer, butter and ghee',
      ['diary', 'doodh', 'dahi', 'lactose', 'milk products']),
  pulses('Dals & pulses', 'Dals, rajma, chana, soya and besan',
      ['daal', 'lentil', 'legume', 'vrat', 'fast', 'navratri']),
  grains('All grains', 'Rice, wheat, millets, oats, poha and bread',
      ['anaj', 'cereal', 'millet', 'vrat', 'fast', 'navratri']),
  riceWheat('Rice & wheat', 'Roti, rice, poha, sooji and bread',
      ['chawal', 'gehun', 'atta', 'chapati']),
  onionGarlic('Onion & garlic', 'Satvik cooking',
      ['pyaz', 'pyaaz', 'lehsun', 'lahsun', 'sattvic', 'satvic']),
  nuts('Nuts & seeds', 'Peanuts, almonds and til',
      ['peanut', 'moongphali', 'badam', 'sesame']);

  const AvoidGroup(this.label, this.description, this.aliases);
  final String label;
  final String description;

  /// Other words people type for the group: Hindi names, common misspellings,
  /// the occasion it is kept for.
  final List<String> aliases;

  /// Whether the group can appear at all on a [diet] — meat never reaches a
  /// vegetarian plan, so there is nothing to avoid.
  /// "All non-veg" is offered only to non-vegetarians: for an eggetarian it
  /// would mean just eggs, which [egg] already says without talking about
  /// meat.
  bool relevantTo(DietType diet) => switch (this) {
        AvoidGroup.nonVeg ||
        AvoidGroup.meat ||
        AvoidGroup.chicken ||
        AvoidGroup.fish =>
          diet == DietType.nonveg,
        AvoidGroup.egg => diet != DietType.veg,
        _ => true,
      };
}

/// A weekly observance: on these days, these people do not eat these things.
///
/// Meals are cooked once for the whole household, so the planner leaves the
/// food out of everyone's meals that day. [memberIds] is kept so the app can
/// say who the day is for.
class DayRule {
  const DayRule({
    required this.memberIds,
    required this.weekdays,
    this.groups = const {},
    this.ingredients = const {},
  });

  final Set<String> memberIds;

  /// 0 = Monday.
  final Set<int> weekdays;
  final Set<AvoidGroup> groups;

  /// Individual ingredient ids, for anything the groups do not cover.
  final Set<String> ingredients;

  bool get isEmpty =>
      memberIds.isEmpty ||
      weekdays.isEmpty ||
      (groups.isEmpty && ingredients.isEmpty);

  /// The rule as it applies on [diet]: groups that cannot reach the plate are
  /// dropped, and "All non-veg" becomes "Eggs" for an eggetarian, which is
  /// all it still rules out.
  DayRule forDiet(DietType diet) => DayRule(
        memberIds: memberIds,
        weekdays: weekdays,
        groups: {
          for (final g in groups)
            if (g == AvoidGroup.nonVeg && diet == DietType.egg)
              AvoidGroup.egg
            else if (g.relevantTo(diet))
              g,
        },
        ingredients: ingredients,
      );

  DayRule copyWith({Set<String>? memberIds}) => DayRule(
        memberIds: memberIds ?? this.memberIds,
        weekdays: weekdays,
        groups: groups,
        ingredients: ingredients,
      );

  Map<String, dynamic> toJson() => {
        'memberIds': memberIds.toList(),
        'weekdays': weekdays.toList()..sort(),
        'groups': groups.map((g) => g.name).toList(),
        'ingredients': ingredients.toList(),
      };

  static DayRule fromJson(Map<String, dynamic> j) => DayRule(
        memberIds: {...(j['memberIds'] as List).cast<String>()},
        weekdays: {...(j['weekdays'] as List).cast<int>()},
        groups: {
          for (final g in (j['groups'] as List? ?? []).cast<String>())
            AvoidGroup.values.byName(g)
        },
        ingredients: {...(j['ingredients'] as List? ?? []).cast<String>()},
      );
}

/// How often the household buys fresh food, which decides how long perishables
/// must last between shops.
enum ShoppingRhythm {
  weekly('Once a week', 'One big shop for everything.', [0]),
  twice('Twice a week', 'A main shop, and fresh vegetables and dairy again '
      'mid-week.', [0, 3]),
  frequent('Every two days', 'The sabziwala or market every other day.',
      [0, 2, 4, 6]);

  const ShoppingRhythm(this.label, this.description, this.tripDays);
  final String label;
  final String description;

  /// Day offsets into the week on which a shop happens. Day 0 is the day the
  /// plan starts, when everything long-lasting is bought.
  final List<int> tripDays;

  /// The most recent shop on or before [day].
  int tripFor(int day) => tripDays.lastWhere((t) => t <= day);
}

/// ICMR-NIN 2020 reference adult body weights, used to prefill household
/// members whose exact measurements the user does not want to enter.
const double referenceManKg = 65;
const double referenceWomanKg = 55;
const double referenceManCm = 168;
const double referenceWomanCm = 155;

/// Approximate reference body size by age band, so a child added to the
/// household is not modelled as a small adult.
///
/// Values follow the shape of the ICMR-NIN reference body weights for Indian
/// children. They are approximations used only to prefill a member the user
/// chose not to measure; anyone who enters real figures overrides them.
({double kg, double cm}) referenceBodyFor(int age, Sex sex) {
  final male = sex == Sex.male;
  if (age <= 3) return (kg: 12.9, cm: 90);
  if (age <= 6) return (kg: 18.3, cm: 109);
  if (age <= 9) return (kg: 25.3, cm: 128);
  if (age <= 12) return male ? (kg: 34.9, cm: 143) : (kg: 36.4, cm: 144);
  if (age <= 15) return male ? (kg: 50.5, cm: 159) : (kg: 49.6, cm: 153);
  if (age <= 17) return male ? (kg: 64.4, cm: 172) : (kg: 55.7, cm: 160);
  return male
      ? (kg: referenceManKg, cm: referenceManCm)
      : (kg: referenceWomanKg, cm: referenceWomanCm);
}

class HouseholdMember {
  const HouseholdMember({
    required this.id,
    required this.name,
    required this.age,
    required this.sex,
    required this.weightKg,
    required this.heightCm,
    required this.activity,
    required this.goal,
    this.isPrimary = false,
  });

  final String id;
  final String name;
  final int age;
  final Sex sex;
  final double weightKg;
  final double heightCm;
  final ActivityLevel activity;
  final Goal goal;
  final bool isPrimary;

  /// A member the user added without full measurements: fall back to the
  /// age- and sex-appropriate reference body size.
  factory HouseholdMember.reference({
    required String id,
    required String name,
    required int age,
    required Sex sex,
    ActivityLevel activity = ActivityLevel.light,
    Goal goal = Goal.maintain,
  }) {
    final body = referenceBodyFor(age, sex);
    return HouseholdMember(
      id: id,
      name: name,
      age: age,
      sex: sex,
      weightKg: body.kg,
      heightCm: body.cm,
      activity: activity,
      goal: goal,
    );
  }

  /// Children and adolescents are still growing, so protein needs per kg are
  /// higher than the adult RDA and energy needs are lower in absolute terms.
  bool get isChild => age < 18;

  HouseholdMember copyWith({
    String? name,
    int? age,
    Sex? sex,
    double? weightKg,
    double? heightCm,
    ActivityLevel? activity,
    Goal? goal,
  }) =>
      HouseholdMember(
        id: id,
        name: name ?? this.name,
        age: age ?? this.age,
        sex: sex ?? this.sex,
        weightKg: weightKg ?? this.weightKg,
        heightCm: heightCm ?? this.heightCm,
        activity: activity ?? this.activity,
        goal: goal ?? this.goal,
        isPrimary: isPrimary,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'age': age,
        'sex': sex.name,
        'weightKg': weightKg,
        'heightCm': heightCm,
        'activity': activity.name,
        'goal': goal.name,
        'isPrimary': isPrimary,
      };

  static HouseholdMember fromJson(Map<String, dynamic> j) => HouseholdMember(
        id: j['id'] as String,
        name: j['name'] as String,
        age: j['age'] as int,
        sex: Sex.values.byName(j['sex'] as String),
        weightKg: (j['weightKg'] as num).toDouble(),
        heightCm: (j['heightCm'] as num).toDouble(),
        activity: ActivityLevel.values.byName(j['activity'] as String),
        goal: Goal.values.byName(j['goal'] as String),
        isPrimary: j['isPrimary'] as bool? ?? false,
      );
}

/// Everything the planner needs to know about the household.
class Profile {
  const Profile({
    required this.members,
    required this.diet,
    this.disliked = const {},
    this.liked = const {},
    this.allergens = const {},
    this.pantry = const {},
    this.includeSnacks = true,
    this.dayRules = const [],
    this.shopping = ShoppingRhythm.twice,
  });

  final List<HouseholdMember> members;
  final DietType diet;

  /// Ingredient ids the household would rather avoid (soft — heavily penalised).
  final Set<String> disliked;

  /// Ingredient ids the household particularly likes (soft — rewarded).
  final Set<String> liked;

  /// Ingredient ids that must never appear (hard exclusion).
  final Set<String> allergens;

  /// Ingredient ids already at home, so they are dropped from the shopping list.
  final Set<String> pantry;

  final bool includeSnacks;

  /// Foods given up on particular days of the week.
  final List<DayRule> dayRules;

  final ShoppingRhythm shopping;

  /// Every rule that applies on [weekday] (0 = Monday).
  Iterable<DayRule> rulesOn(int weekday) =>
      dayRules.where((r) => r.weekdays.contains(weekday));

  int get householdSize => members.length;

  HouseholdMember get primary =>
      members.firstWhere((m) => m.isPrimary, orElse: () => members.first);

  Profile copyWith({
    List<HouseholdMember>? members,
    DietType? diet,
    Set<String>? disliked,
    Set<String>? liked,
    Set<String>? allergens,
    Set<String>? pantry,
    bool? includeSnacks,
    List<DayRule>? dayRules,
    ShoppingRhythm? shopping,
  }) =>
      Profile(
        members: members ?? this.members,
        diet: diet ?? this.diet,
        disliked: disliked ?? this.disliked,
        liked: liked ?? this.liked,
        allergens: allergens ?? this.allergens,
        pantry: pantry ?? this.pantry,
        includeSnacks: includeSnacks ?? this.includeSnacks,
        dayRules: dayRules ?? this.dayRules,
        shopping: shopping ?? this.shopping,
      );

  Map<String, dynamic> toJson() => {
        'members': members.map((m) => m.toJson()).toList(),
        'diet': diet.name,
        'disliked': disliked.toList(),
        'liked': liked.toList(),
        'allergens': allergens.toList(),
        'pantry': pantry.toList(),
        'includeSnacks': includeSnacks,
        'dayRules': dayRules.map((r) => r.toJson()).toList(),
        'shopping': shopping.name,
      };

  static Profile fromJson(Map<String, dynamic> j) => Profile(
        members: (j['members'] as List)
            .map((e) => HouseholdMember.fromJson(e as Map<String, dynamic>))
            .toList(),
        diet: DietType.values.byName(j['diet'] as String),
        disliked: {...(j['disliked'] as List? ?? []).cast<String>()},
        liked: {...(j['liked'] as List? ?? []).cast<String>()},
        allergens: {...(j['allergens'] as List? ?? []).cast<String>()},
        pantry: {...(j['pantry'] as List? ?? []).cast<String>()},
        includeSnacks: j['includeSnacks'] as bool? ?? true,
        dayRules: [
          for (final r in (j['dayRules'] as List? ?? []))
            DayRule.fromJson(r as Map<String, dynamic>)
        ],
        shopping: ShoppingRhythm.values
                .where((s) => s.name == j['shopping'])
                .firstOrNull ??
            ShoppingRhythm.twice,
      );
}
