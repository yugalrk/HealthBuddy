/// Weekly nutrient balance, and why the targets are what they are.
library;

import 'package:flutter/material.dart';

import '../../engine/targets.dart';
import '../../models/profile.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

class NutritionScreen extends StatelessWidget {
  const NutritionScreen({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final planned = app.weeklyPlanned;
    final target = app.weeklyTargets;
    final scheme = Theme.of(context).colorScheme;

    if (planned == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(title: Text('Nutrition')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          sliver: SliverList.list(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Across the whole week',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        'Individual days vary on purpose — a lighter lunch is '
                        'made up at dinner, and a short day is made up the '
                        'next. What matters is the weekly total.',
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      NutrientBar(
                          label: 'Energy',
                          planned: planned.kcal,
                          target: target.kcal,
                          unit: 'kcal'),
                      NutrientBar(
                          label: 'Protein',
                          planned: planned.protein,
                          target: target.protein,
                          unit: 'g'),
                      NutrientBar(
                          label: 'Fat',
                          planned: planned.fat,
                          target: target.fat,
                          unit: 'g'),
                      NutrientBar(
                          label: 'Carbohydrate',
                          planned: planned.carb,
                          target: target.carb,
                          unit: 'g'),
                      NutrientBar(
                          label: 'Fibre',
                          planned: planned.fibre,
                          target: target.fibre,
                          unit: 'g'),
                    ],
                  ),
                ),
              ),
              const SectionHeader('Micronutrients to watch'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NutrientBar(
                        label: 'Iron',
                        planned: planned.iron,
                        target: target.iron,
                        unit: 'mg',
                        caption:
                            'Indian diets commonly fall short. Dals, kala '
                            'chana, bajra and til are the strongest sources '
                            'here — spinach is not, despite its reputation.',
                      ),
                      NutrientBar(
                        label: 'Calcium',
                        planned: planned.calcium,
                        target: target.calcium,
                        unit: 'mg',
                        caption:
                            'Curd, paneer, milk, ragi and til carry most of '
                            'this.',
                      ),
                    ],
                  ),
                ),
              ),
              const SectionHeader('Not tracked yet'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 20, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          app.profile.diet == DietType.veg
                              ? 'Vitamin B12 is not in our food data, and a '
                                  'vegetarian diet is the classic place to run '
                                  'short of it. Dairy helps; if you eat little '
                                  'dairy, ask your doctor about testing.'
                              : 'Vitamin B12 and vitamin D are not tracked. '
                                  'Both are worth asking your doctor about if '
                                  'you have symptoms.',
                          style: const TextStyle(fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SectionHeader('How your targets are worked out'),
              ...memberBreakdown(app.profile).map((mt) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(mt.member.name,
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700)),
                                ),
                                Text(
                                  '${mt.targets.kcal.round()} kcal/day',
                                  style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${mt.member.age} years · '
                              '${mt.member.sex.name} · '
                              '${mt.member.weightKg.round()} kg · '
                              '${mt.member.activity.label.toLowerCase()}',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Protein ${mt.targets.protein.round()} g/day '
                              '(${mt.proteinGPerKg.toStringAsFixed(2)} g per kg)',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            if (app.profile.diet == DietType.veg) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Raised for a vegetarian, cereal-based diet, '
                                'as ICMR-NIN 2020 recommends.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  )),
              const SizedBox(height: 8),
              Text(
                'Energy needs use the Mifflin-St Jeor equation. Nutrient '
                'targets follow ICMR-NIN 2020 (Nutrient Requirements for '
                'Indians). This is general guidance, not medical advice.',
                style: TextStyle(
                    fontSize: 12, height: 1.4, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
