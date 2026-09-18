# HealthBuddy

A weekly meal planner and shopping-list builder for Indian households.

Tell it who eats at home, what you like and what you are aiming for, and it
plans seven days of meals sized for your household, with one categorised
shopping list to match.

## What makes the planner different

**It optimises the week, not the meal.** A shortfall is carried forward — a
lighter lunch is repaid at dinner, a short Tuesday is repaid on Wednesday. Day
totals vary on purpose; the weekly total is what is held to target.

**It takes vegetarian protein seriously.** ICMR-NIN 2020 sets the adult protein
RDA at 0.83 g/kg/day, but states that cereal-based Indian diets need 1 g/kg
because the protein quality is lower. HealthBuddy applies that adjustment and
then actually plans to reach it, using dals, paneer, tofu, soya and sprouts.
This was the app's reason for existing, and the recipe set was extended
specifically because the first version could not hit the target.

**Meals are built as thalis.** Lunch and dinner are a protein `main` plus a
staple whose portion is solved to close the energy gap, optionally with a sabzi
and a side. Making the protein main structurally mandatory is what stops a
near-zero-protein gourd dish becoming the centre of a meal.

**Iron and calcium are planned for**, not left to chance — they are the two
nutrients Indian diets most often fall short on.

**It keeps the household's days.** No meat on Tuesdays, no onion and garlic on
a fast day, no rice on a particular day: tell it once and those days' meals
leave the food out, for the whole table, every week.

**It plans around shelf life.** It knows paneer keeps three days and palak two,
and how often you shop. Perishables are cooked while they are good, opened
packs are used up before new ones are started, and the shopping list is split
into your shopping days. Anything a whole pack still leaves over is shown, not
hidden.

**It adjusts to what actually happened.** Each evening it asks how the day
went. If a meal was skipped, halved or eaten out, the rest of the week is
planned again: part of the shortfall is made up (at most 20% a day), and the
food bought for the missed meal is cooked before it goes off.

## Layout

```
lib/
  models/     profile, food (ingredient/recipe/nutrients), plan
  engine/     targets, planner, stock, adapt,
              shopping_list                        <- pure Dart, no Flutter
  data/       food_data.dart, repositories/
  state/      app_state.dart
  ui/         onboarding, plan, shopping, nutrition, profile
assets/seed/  ingredients.json, recipes.json
test/         91 tests
tool/         demo_plan, spoilage_report, diagnose, bench, make_icons
docs/         NUTRITION_SOURCES.md, RELEASE.md
store/        listing copy, privacy policy, graphics
```

The engine has no Flutter dependency, so it is fully testable headlessly —
which matters here, because this was developed in WSL2 with no emulator.

## Getting started

```bash
flutter test                    # verify the engine
dart run tool/demo_plan.dart    # see a week and its shopping list
flutter run -d web-server --web-port 8080   # preview the UI in a browser
```

See `docs/RELEASE.md` for the toolchain and Play Store steps.

## Data provenance

Nutrition values come from the Indian Food Composition Tables 2017 (ICMR-NIN)
and USDA FoodData Central, and every ingredient records which. Eight items are
still flagged as estimates and must be verified before production — see
`docs/NUTRITION_SOURCES.md`.

## Disclaimer

General nutrition guidance, not medical advice.
