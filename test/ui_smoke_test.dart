import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbuddy/data/food_data.dart';
import 'package:healthbuddy/data/repositories/repositories.dart';
import 'package:healthbuddy/engine/day_score.dart';
import 'package:healthbuddy/models/food.dart';
import 'package:healthbuddy/models/plan.dart';
import 'package:healthbuddy/models/profile.dart';
import 'package:healthbuddy/state/app_state.dart';
import 'package:healthbuddy/ui/home_shell.dart';
import 'package:healthbuddy/ui/onboarding/onboarding_screen.dart';
import 'package:healthbuddy/ui/theme.dart';

/// In-memory repositories so the UI can be exercised without a device or
/// platform channels.
class FakeProfileRepo implements ProfileRepository {
  FakeProfileRepo([this._p]);
  Profile? _p;
  @override
  Future<Profile?> load() async => _p;
  @override
  Future<void> save(Profile p) async => _p = p;
  @override
  Future<void> clear() async => _p = null;
}

class FakeScoreRepo implements ScoreRepository {
  ScoreLog log = ScoreLog();
  @override
  Future<ScoreLog> load() async => log;
  @override
  Future<void> save(ScoreLog l) async => log = l;
  @override
  Future<void> clear() async => log = ScoreLog();
}

class FakePlanRepo implements PlanRepository {
  SavedWeek? _w;
  @override
  Future<SavedWeek?> load() async => _w;
  @override
  Future<void> save(SavedWeek w) async => _w = w;
  @override
  Future<void> clear() async => _w = null;
}

FoodData loadFood() => FoodData.parse(
      ingredientsJson: File('assets/seed/ingredients.json').readAsStringSync(),
      recipesJson: File('assets/seed/recipes.json').readAsStringSync(),
    );

Profile sampleProfile() => Profile(
      members: [
        const HouseholdMember(
          id: 'p1',
          name: 'You',
          age: 30,
          sex: Sex.male,
          weightKg: 70,
          heightCm: 175,
          activity: ActivityLevel.moderate,
          goal: Goal.maintain,
          isPrimary: true,
        ),
        HouseholdMember.reference(
            id: 'p2', name: 'Child', age: 9, sex: Sex.female),
      ],
      diet: DietType.veg,
    );

Widget wrap(Widget child) => MaterialApp(
      theme: buildTheme(Brightness.light),
      home: child,
    );

/// The home shell, rebuilt whenever the app state changes — as main.dart does.
Widget live(AppState app) => ListenableBuilder(
      listenable: app,
      builder: (_, _) => HomeShell(app: app),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('onboarding renders and can be completed', (tester) async {
    final food = loadFood();
    Profile? result;

    await tester.pumpWidget(wrap(OnboardingScreen(
      ingredients: food.ingredients,
      onComplete: (p) => result = p,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Plan your week, eat properly'), findsOneWidget);
    expect(find.textContaining('ICMR-NIN'), findsWidgets);

    // Walk the whole flow using the primary button.
    for (var i = 0; i < 10; i++) {
      final button = find.widgetWithText(FilledButton, 'Continue');
      if (button.evaluate().isEmpty) break;
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.widgetWithText(FilledButton, 'Create my plan'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.members.single.isPrimary, isTrue);
    expect(result!.diet, DietType.veg);
  });

  testWidgets('household size flows through to the shopping list',
      (tester) async {
    final app = AppState(
      profileRepo: FakeProfileRepo(sampleProfile()),
      planRepo: FakePlanRepo(),
      scoreRepo: FakeScoreRepo(),
      useBackgroundIsolate: false,
      // A Monday morning, so the week starts on Monday.
      clock: () => DateTime(2026, 9, 21, 9),
    );
    // Real file I/O, so it must run outside the fake clock.
    await tester.runAsync(() async {
      await app.init();
      await app.generateNewWeek(seed: 5);
    });

    expect(app.state, LoadState.ready);
    expect(app.plan, isNotNull);
    expect(app.shoppingList, isNotNull);
    expect(app.shoppingList!.itemCount, greaterThan(10));

    await tester.pumpWidget(wrap(HomeShell(app: app)));
    await tester.pumpAndSettle();

    // Plan tab
    expect(find.text('This week'), findsWidgets);
    expect(find.text('Monday'), findsOneWidget);

    // Shopping tab
    await tester.tap(find.text('Shopping'));
    await tester.pumpAndSettle();
    expect(find.text('Shopping list'), findsWidgets);
    expect(find.textContaining('2 people'), findsWidgets);

    // Nutrition tab
    await tester.tap(find.text('Nutrition'));
    await tester.pumpAndSettle();
    expect(find.text('Protein'), findsWidgets);

    // Household tab
    await tester.tap(find.text('Household'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vegetarian'), findsWidgets);
  });

  testWidgets('ticking a shopping item persists in state', (tester) async {
    final app = AppState(
      profileRepo: FakeProfileRepo(sampleProfile()),
      planRepo: FakePlanRepo(),
      scoreRepo: FakeScoreRepo(),
      useBackgroundIsolate: false,
    );
    await tester.runAsync(() async {
      await app.init();
      await app.generateNewWeek(seed: 6);
    });

    final first =
        app.shoppingList!.toBuy.values.first.first.ingredient.id;
    expect(app.checkedItems, isEmpty);
    app.toggleChecked(first);
    expect(app.checkedItems, contains(first));
    app.toggleChecked(first);
    expect(app.checkedItems, isEmpty);
  });

  testWidgets('a fresh install lands on onboarding', (tester) async {
    final app = AppState(
      profileRepo: FakeProfileRepo(),
      planRepo: FakePlanRepo(),
      scoreRepo: FakeScoreRepo(),
      useBackgroundIsolate: false,
    );
    await tester.runAsync(app.init);
    expect(app.state, LoadState.onboarding);
  });

  testWidgets('a day rule can be added during set-up', (tester) async {
    final food = loadFood();
    Profile? result;
    await tester.pumpWidget(wrap(OnboardingScreen(
      ingredients: food.ingredients,
      onComplete: (p) => result = p,
    )));
    await tester.pumpAndSettle();

    while (find.text('Any days you avoid certain foods?').evaluate().isEmpty) {
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Add a day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tue'));
    await tester.scrollUntilVisible(find.text('Onion & garlic'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.ensureVisible(find.text('Onion & garlic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Onion & garlic'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Tuesday'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every two days'));
    await tester.tap(find.widgetWithText(FilledButton, 'Create my plan'));
    await tester.pumpAndSettle();

    final rule = result!.dayRules.single;
    expect(rule.weekdays, {1});
    expect(rule.groups, {AvoidGroup.onionGarlic});
    expect(rule.memberIds, {'primary'});
    expect(result!.shopping, ShoppingRhythm.frequent);
  });

  testWidgets('the evening prompt asks how the day went and adapts',
      (tester) async {
    var now = DateTime(2026, 9, 21, 9);
    final repo = FakePlanRepo();
    final app = AppState(
      profileRepo: FakeProfileRepo(sampleProfile()),
      planRepo: repo,
      scoreRepo: FakeScoreRepo(),
      useBackgroundIsolate: false,
      clock: () => now,
    );
    await tester.runAsync(() async {
      await app.init();
      await app.generateNewWeek(seed: 7);
    });

    // Morning: nothing to ask yet.
    expect(app.pendingFeedbackDay, isNull);

    now = DateTime(2026, 9, 21, 20);
    expect(app.pendingFeedbackDay, 0);
    await tester.pumpWidget(wrap(live(app)));
    await tester.pumpAndSettle();
    expect(find.text('How did today go?'), findsOneWidget);

    // A skipped dinner reshapes the rest of the week.
    final before = app.plan!.toJson();
    await tester.runAsync(() => app.recordFeedback(
        const DayFeedback(0, {MealType.dinner: MealOutcome.skipped})));
    await tester.pumpAndSettle();
    expect(app.pendingFeedbackDay, isNull);
    expect(app.lastAdaptation, isNotNull);
    expect(app.plan!.toJson()['days'][0], before['days'][0]);
    expect(find.text('Rest of the week adjusted'), findsOneWidget);
    expect(find.text('skipped'), findsOneWidget);

    // The next morning, yesterday's answer is remembered after a restart.
    now = DateTime(2026, 9, 22, 8);
    final reopened = AppState(
      profileRepo: FakeProfileRepo(sampleProfile()),
      planRepo: repo,
      scoreRepo: FakeScoreRepo(),
      useBackgroundIsolate: false,
      clock: () => now,
    );
    await tester.runAsync(reopened.init);
    expect(reopened.todayIndex, 1);
    expect(reopened.progress!.feedback[0]!.outcomeOf(MealType.dinner),
        MealOutcome.skipped);
    expect(reopened.plan!.toJson(), app.plan!.toJson());
    expect(reopened.pendingFeedbackDay, isNull);
  });

  testWidgets('an unanswered day is asked about the next morning',
      (tester) async {
    var now = DateTime(2026, 9, 21, 9);
    final app = AppState(
      profileRepo: FakeProfileRepo(sampleProfile()),
      planRepo: FakePlanRepo(),
      scoreRepo: FakeScoreRepo(),
      useBackgroundIsolate: false,
      clock: () => now,
    );
    await tester.runAsync(() async {
      await app.init();
      await app.generateNewWeek(seed: 8);
    });
    now = DateTime(2026, 9, 23, 9);
    expect(app.pendingFeedbackDay, 0);

    await tester.pumpWidget(wrap(live(app)));
    await tester.pumpAndSettle();
    expect(find.text('How did Monday go?'), findsOneWidget);
    await tester.tap(find.text('All as planned'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(app.pendingFeedbackDay, 1);
    expect(find.text('How did yesterday go?'), findsOneWidget);
  });

  testWidgets('every screen fits a small phone', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final profile = Profile(
      members: [
        ...sampleProfile().members,
        HouseholdMember.reference(
            id: 'p3', name: 'Grandmother', age: 70, sex: Sex.female),
      ],
      diet: DietType.nonveg,
      dayRules: const [
        DayRule(
          memberIds: {'p1', 'p3'},
          weekdays: {0, 1, 3},
          groups: {AvoidGroup.nonVeg, AvoidGroup.onionGarlic},
          ingredients: {'paneer'},
        ),
      ],
    );
    var now = DateTime(2026, 9, 23, 21); // a Wednesday evening
    final app = AppState(
      profileRepo: FakeProfileRepo(profile),
      planRepo: FakePlanRepo(),
      scoreRepo: FakeScoreRepo(),
      useBackgroundIsolate: false,
      clock: () => now,
    );
    await tester.runAsync(() async {
      await app.init();
      await app.generateNewWeek(seed: 9);
      await app.recordFeedback(const DayFeedback(0, {
        MealType.lunch: MealOutcome.other,
        MealType.dinner: MealOutcome.half,
      }));
    });
    now = DateTime(2026, 9, 24, 21);

    await tester.pumpWidget(wrap(live(app)));
    await tester.pumpAndSettle();
    expect(find.text('Rest of the week adjusted'), findsOneWidget);

    await tester.tap(find.text('Something changed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Something else').first);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Something else').first)).pop();
    await tester.pumpAndSettle();

    for (final tab in ['Shopping', 'Nutrition', 'Household']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView).last, const Offset(0, -3000));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Shopping').last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('By nutrition'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('By nutrition'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('By nutrition'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('PROTEIN FOODS'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('PROTEIN FOODS'), findsWidgets);
    await tester.pumpAndSettle();
  });

  testWidgets('foods can be searched, and non-veg groups picked one by one',
      (tester) async {
    final food = loadFood();
    Profile? result;
    await tester.pumpWidget(wrap(OnboardingScreen(
      ingredients: food.ingredients,
      onComplete: (p) => result = p,
    )));
    await tester.pumpAndSettle();

    Future<void> tapShown(String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.pumpAndSettle();
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    Future<void> continueUntil(String title) async {
      while (find.text(title).evaluate().isEmpty) {
        await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
        await tester.pumpAndSettle();
      }
    }

    await continueUntil('What do you eat?');
    await tester.tap(find.text('Non-vegetarian'));
    await tester.pumpAndSettle();

    // Preferences: search narrows the chips.
    await continueUntil('Anything you avoid?');
    expect(find.text('Paneer'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'spin');
    await tester.pumpAndSettle();
    expect(find.text('Palak (spinach)'), findsOneWidget);
    expect(find.text('Paneer'), findsNothing);
    await tester.tap(find.text('Palak (spinach)'));
    await tester.pumpAndSettle();
    // A group turns up in the same search, and marks all its foods at once.
    await tester.enterText(find.byType(TextField), 'diary');
    await tester.pumpAndSettle();
    await tapShown('Dairy');
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing matches'), findsOneWidget);

    // Day rule: chicken and fish only, plus a searched-for food.
    await continueUntil('Any days you avoid certain foods?');
    await tester.tap(find.text('Add a day'));
    await tester.pumpAndSettle();
    for (final t in ['Tue', 'Chicken', 'Fish & seafood']) {
      await tapShown(t);
    }
    expect(
        tester
            .widget<CheckboxListTile>(
                find.widgetWithText(CheckboxListTile, 'Fish & seafood'))
            .value,
        isTrue);
    // The search box sits above the groups.
    await tester.scrollUntilVisible(find.byType(TextField), -300,
        scrollable: find.byType(Scrollable).last);
    await tester.enterText(find.byType(TextField), 'brinj');
    await tester.pumpAndSettle();
    await tapShown('Baingan (brinjal)');
    // Groups are found by search too; a wider one replaces the narrower
    // groups it covers.
    await tester.enterText(find.byType(TextField), 'dal');
    await tester.pumpAndSettle();
    await tapShown('Dals & pulses');
    await tester.enterText(find.byType(TextField), 'nonveg');
    await tester.pumpAndSettle();
    expect(find.text('Palak (spinach)'), findsNothing);
    await tapShown('All non-veg');
    // Save is pinned below the list, so no scrolling is needed to reach it.
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No dals & pulses, non-veg or baingan'),
        findsOneWidget);

    await continueUntil('How often do you shop for fresh food?');
    await tester.tap(find.widgetWithText(FilledButton, 'Create my plan'));
    await tester.pumpAndSettle();

    expect(result!.liked, {'palak'});
    expect(result!.disliked,
        containsAll(['milk', 'curd', 'paneer', 'butter', 'ghee']));
    expect(result!.disliked, isNot(contains('tofu')));
    final rule = result!.dayRules.single;
    expect(rule.groups, {AvoidGroup.pulses, AvoidGroup.nonVeg});
    expect(rule.ingredients, {'baingan'});
  });

  testWidgets('a vegetarian household never sees meat, fish or eggs',
      (tester) async {
    final food = loadFood();
    await tester.pumpWidget(wrap(OnboardingScreen(
      ingredients: food.ingredients,
      onComplete: (_) {},
    )));
    await tester.pumpAndSettle();

    final nonVeg = RegExp(r'meat|chicken|fish|egg|non-veg|mutton',
        caseSensitive: false);
    void expectNoNonVeg(String where) => expect(
        find.textContaining(nonVeg), findsNothing,
        reason: 'non-veg wording on $where');

    // Vegetarian is the default diet.
    while (find.text('Anything you avoid?').evaluate().isEmpty) {
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
    }
    expectNoNonVeg('the avoid-foods page');
    for (final q in ['meat', 'chicken', 'anda', 'nonveg']) {
      await tester.enterText(find.byType(TextField), q);
      await tester.pumpAndSettle();
      expect(find.byType(FilterChip), findsNothing, reason: q);
    }
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Any days you avoid certain foods?'), findsOneWidget);
    expectNoNonVeg('the day-rule page');
    await tester.tap(find.text('Add a day'));
    await tester.pumpAndSettle();
    expectNoNonVeg('the day-rule sheet');
    await tester.scrollUntilVisible(find.byType(TextField), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.enterText(find.byType(TextField), 'meat');
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing matches'), findsOneWidget);
  });


  testWidgets('the week strip picks a day, and the pantry opens as a sheet',
      (tester) async {
    final app = AppState(
      profileRepo: FakeProfileRepo(sampleProfile()),
      planRepo: FakePlanRepo(),
      scoreRepo: FakeScoreRepo(),
      useBackgroundIsolate: false,
      clock: () => DateTime(2026, 9, 21, 9),
    );
    await tester.runAsync(() async {
      await app.init();
      await app.generateNewWeek(seed: 2);
    });
    await tester.pumpWidget(wrap(live(app)));
    await tester.pumpAndSettle();

    // Opens on today, one day at a time.
    final today = app.plan!.days[app.todayIndex].dayName;
    final next = app.plan!.days[app.todayIndex + 1].dayName;
    expect(find.text(today), findsOneWidget);
    expect(find.text(next), findsNothing);
    await tester.tap(find.text(next.substring(0, 3)));
    await tester.pumpAndSettle();
    expect(find.text(next), findsOneWidget);
    expect(find.text('Amounts and totals for all 2 of you'), findsOneWidget);

    await tester.tap(find.text('Household').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Already at home'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Already at home'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'salt');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Salt'));
    await tester.pumpAndSettle();
    expect(app.profile.pantry, contains('salt'));
  });


  testWidgets('the evening check-in scores the day, shown under Your days',
      (tester) async {
    final now = DateTime(2026, 9, 21, 20);
    final scores = FakeScoreRepo();
    final app = AppState(
      profileRepo: FakeProfileRepo(sampleProfile()),
      planRepo: FakePlanRepo(),
      scoreRepo: scores,
      useBackgroundIsolate: false,
      clock: () => now,
    );
    await tester.runAsync(() async {
      await app.init();
      await app.generateNewWeek(seed: 7);
    });

    // Before any check-in, the Household tab explains how scoring works.
    await tester.pumpWidget(wrap(live(app)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Household').last);
    await tester.pumpAndSettle();
    expect(find.text('YOUR DAYS'), findsOneWidget);
    expect(find.textContaining('gets a score out of 100'), findsOneWidget);

    // Check in through the sheet: meals as planned, two junk snacks.
    await tester.tap(find.text('Plan').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Something changed'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('3 or more'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.widgetWithText(ChoiceChip, '2'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final today = app.scores.on(DateTime(2026, 9, 21))!;
    expect(today.junkSnacks, 2);
    expect(today.misses, contains('2 junk snacks'));
    expect(scores.log.days, hasLength(1), reason: 'saved');
    expect(find.textContaining('Your score: ${today.score}/100'),
        findsOneWidget);

    // The same day as planned, without junk, scores higher.
    final clean = app.scoreFor(DayFeedback(0, {
      for (final m in app.plan!.days[0].meals) m.type: MealOutcome.asPlanned
    }));
    expect(clean.score, greaterThanOrEqualTo(today.score + 20));
    // Skipping lunch and dinner costs points too.
    final skipped = app.scoreFor(const DayFeedback(0, {
      MealType.lunch: MealOutcome.skipped,
      MealType.dinner: MealOutcome.skipped,
    }));
    expect(skipped.score, lessThan(clean.score - 20));
    expect(skipped.misses.first, anyOf(startsWith('Protein'), startsWith('Calories')));

    // Shown on the Household tab; tapping it explains the points.
    await tester.tap(find.text('Household').last);
    await tester.pumpAndSettle();
    expect(find.text('${today.score}'), findsWidgets);
    expect(find.text('Today'), findsOneWidget);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('Where the points went'), findsOneWidget);
    expect(find.text('• 2 junk snacks'), findsOneWidget);
    expect(find.text('0 / 20'), findsOneWidget); // no-junk points

    // Changing the answer replaces the day's score rather than adding one.
    await tester.runAsync(() => app.recordFeedback(DayFeedback(0, {
          for (final m in app.plan!.days[0].meals)
            m.type: MealOutcome.asPlanned
        })));
    expect(app.scores.days, hasLength(1));
    expect(app.scores.on(DateTime(2026, 9, 21))!.junkSnacks, 0);

    // Reset clears the history.
    await tester.runAsync(app.resetAll);
    expect(app.scores.isEmpty, isTrue);
    expect(scores.log.isEmpty, isTrue);
  });

  testWidgets('days reported before scoring existed are scored on launch',
      (tester) async {
    final plans = FakePlanRepo();
    final first = AppState(
      profileRepo: FakeProfileRepo(sampleProfile()),
      planRepo: plans,
      scoreRepo: FakeScoreRepo(),
      useBackgroundIsolate: false,
      clock: () => DateTime(2026, 9, 21, 20),
    );
    await tester.runAsync(() async {
      await first.init();
      await first.generateNewWeek(seed: 3);
      await first.recordFeedback(
          const DayFeedback(0, {MealType.lunch: MealOutcome.half}));
    });

    // A fresh score history, as after updating the app.
    final scores = FakeScoreRepo();
    final later = AppState(
      profileRepo: FakeProfileRepo(sampleProfile()),
      planRepo: plans,
      scoreRepo: scores,
      useBackgroundIsolate: false,
      clock: () => DateTime(2026, 9, 22, 9),
    );
    await tester.runAsync(later.init);
    expect(later.scores.on(DateTime(2026, 9, 21)), isNotNull);
    expect(scores.log.days, hasLength(1));
  });

}

