import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbuddy/data/food_data.dart';
import 'package:healthbuddy/data/repositories/repositories.dart';
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
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -250));
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

}

