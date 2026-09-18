# Nutrition data sources and review status

HealthBuddy makes dietary recommendations, so the provenance of every number matters.
This document records where the data came from and what still needs verification.

## Source tags

Every ingredient in `lib/data/seed/ingredients.json` carries a `src` field:

| Tag | Meaning | Count |
|---|---|---|
| `ifct2017` | Indian Food Composition Tables 2017, ICMR-NIN | 46 |
| `usda` | USDA FoodData Central (public domain) | 15 |
| `est` | Reasoned estimate — **not yet verified** | 8 |

## Items currently marked `est` — must be verified before production release

These eight were unavailable to me at authoring time in a form I could cite with confidence.
They are plausible and internally consistent, but they are not sourced, and a nutrition app
should not ship unsourced numbers:

- `soya_chunks` — protein is the critical figure here (claimed 52 g/100 g); it drives the
  whole high-protein vegetarian pathway, so it matters most of the eight.
- `brown_rice`, `idli_rava`, `bread_brown` — commercial products; values vary by brand.
- `chicken_curry_cut` — with-bone yield varies; verify edible-portion basis.
- `mirch`, `garam_masala`, `hing` — spices, used in gram quantities, so error here is
  nutritionally negligible but should still be corrected for completeness.

**Action before release:** check each against IFCT 2017, or against the product label for
commercial items, and flip `src` to `ifct2017` / `label`.

## Deliberate correction worth knowing about

`palak` (spinach) iron is recorded as **1.14 mg/100 g**, not the ~17 mg figure that circulates
widely. Older Indian composition tables substantially overstated spinach iron — the value was
contaminated by soil/dust iron in the original assays. IFCT 2017 corrected this sharply downward.

This matters for the app's behaviour: spinach is *not* a strong iron source, and a planner that
believes otherwise would under-deliver iron to exactly the vegetarian users most at risk of
deficiency. Iron targets are met through dals, kala chana, bajra and til instead.

## Protein requirement basis

Targets follow **ICMR-NIN 2020**:

- RDA **0.83 g/kg/day** for adults on a mixed diet.
- **1.0 g/kg/day** where the diet is cereal-dominant / vegetarian. ICMR-NIN notes the lower
  digestibility and quality of cereal-based protein; the 2010 tables used 1.0 g/kg for this reason.
- Higher intakes (1.2–1.6 g/kg) are applied for muscle-gain goals and for fat-loss where lean
  mass preservation matters. These come from sports-nutrition consensus, **not** from ICMR-NIN,
  and are labelled as such in the app.

## Shelf life and buying sizes

Each ingredient carries `shelfLifeDays`: how many days it stays good after purchase when stored
the usual way in an Indian home — the fridge for dairy, meat, fish and leafy greens; a cool shelf
for onions, potatoes and dry goods. Bought on day 0 with a shelf life of 2, an item can be cooked
on days 0 and 1. The planner uses these to keep perishables inside their window and to split the
shopping list into trips.

These are **guidance-grade estimates**, not measured values. They follow the refrigerated storage
times in the USDA FoodKeeper guidance, shortened where Indian conditions (heat, pouch milk, fresh
paneer without preservatives) make the US figure optimistic. Anything of 30 days or more never
limits a week and is set to 180. Items worth a second look before release:

| Item | Days | Note |
|---|---|---|
| Fish (rohu) | 1 | Fresh, not frozen |
| Milk, chicken | 2 | Milk is also marked `dailyFresh`: bought each morning, never stocked |
| Paneer, curd, palak, methi, papaya | 3 | Fresh paneer; home-set or packaged curd |
| Bhindi, tofu, hung curd, bread, beans, matar, banana | 4 | Tofu after opening |
| Coriander, gobi, lauki, capsicum, cucumber | 5 | Coriander wrapped in paper |
| Tomato, curry leaves, green chilli | 7 | Tomatoes in the fridge |
| Egg, cabbage, carrot, lemon | 10–14 | |

`packSize` is the smallest amount that can sensibly be bought. For loose vegetables that is a
*paav* (250 g), because Indian markets sell by the paav and a 500 g minimum made single-person
weeks waste most of every bag. Whole items that cannot be split keep a whole-item size: a
cauliflower, a lauki, a small (500 g) papaya. Chicken and fish are bought by weight at the counter, so their
smallest buy is also 250 g — fish keeps a day, and a 500 g minimum left most of it to spoil for
one or two people.

## Limitations to state in-app

1. Values are for **raw / as-purchased** items. Cooking changes water content and some
   micronutrients; the app does not model cooking losses.
2. Micronutrient coverage is limited to **iron and calcium**. B12 and vitamin D are flagged
   qualitatively (as dietary-pattern risks) rather than quantified, because reliable per-item
   values for Indian foods are not in the dataset.
3. This is **general nutrition guidance, not medical advice**. Anyone with a clinical condition —
   diabetes, CKD, pregnancy, thyroid disorder, eating disorder — should consult a doctor or a
   registered dietitian. The app must say this plainly during onboarding, not bury it.

## References

- ICMR-NIN, *Nutrient Requirements for Indians — RDA and EAR*, 2020 — https://www.nin.res.in/rdabook/brief_note.pdf
- ICMR-NIN, *Indian Food Composition Tables*, 2017
- USDA FoodData Central — https://fdc.nal.usda.gov/
