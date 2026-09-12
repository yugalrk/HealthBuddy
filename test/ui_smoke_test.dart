import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbuddy/data/food_data.dart';
import 'package:healthbuddy/data/repositories/repositories.dart';
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
    for (var i = 0; i < 7; i++) {
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
}
