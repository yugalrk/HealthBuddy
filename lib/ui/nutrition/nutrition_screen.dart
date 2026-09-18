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
        const SliverAppBar(pinned: true, title: Text('Nutrition')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          sliver: SliverList.list(
            children: [
              _RecommendedIntakeCard(app: app),
              if (app.unavoidable.isNotEmpty) ...[
                const SizedBox(height: 12),
                _UnavoidableCard(app: app),
              ],
              const SectionHeader('This week'),
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
                        'next. What matters is the weekly total.'
                        '${app.progress?.feedback.isNotEmpty ?? false ? ' Days you have told us about count what was actually eaten.' : ''}',
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
                          unit: 'g',
                          overIsFine: true),
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
                          unit: 'g',
                          overIsFine: true),
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
                        overIsFine: true,
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
                        overIsFine: true,
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

/// States the household's recommended intake outright, per day and per person,
/// with the reasoning behind each figure.
class _RecommendedIntakeCard extends StatefulWidget {
  const _RecommendedIntakeCard({required this.app});
  final AppState app;

  @override
  State<_RecommendedIntakeCard> createState() => _RecommendedIntakeCardState();
}

class _RecommendedIntakeCardState extends State<_RecommendedIntakeCard> {
  late String _whoId = widget.app.profile.primary.id;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final scheme = Theme.of(context).colorScheme;
    final members = app.profile.members;

    final isHousehold = _whoId == '__household__';
    final targets = isHousehold
        ? app.dailyTargets
        : targetsForMember(
            members.firstWhere((m) => m.id == _whoId, orElse: () => members.first),
            app.profile.diet,
          );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Recommended daily intake',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final m in members)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(m.name),
                        selected: _whoId == m.id,
                        onSelected: (_) => setState(() => _whoId = m.id),
                      ),
                    ),
                  if (members.length > 1)
                    ChoiceChip(
                      label: const Text('Whole home'),
                      selected: isHousehold,
                      onSelected: (_) =>
                          setState(() => _whoId = '__household__'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            for (final g in nutrientGuides)
              _IntakeRow(guide: g, value: g.read(targets)),
            const SizedBox(height: 8),
            Text(
              isHousehold
                  ? 'Everyone in the home added together — this is what a '
                      'day\'s cooking needs to supply.'
                  : 'Tap a name to see that person\'s own numbers.',
              style: TextStyle(
                  fontSize: 12, height: 1.35, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntakeRow extends StatelessWidget {
  const _IntakeRow({required this.guide, required this.value});
  final NutrientGuide guide;
  final double value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 10),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Row(
          children: [
            Expanded(
              child: Text(guide.label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            Text(
              '${value.round()} ${guide.unit}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ],
        ),
        subtitle: Text(
          guide.why,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        children: [
          Text('How this number is set',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(guide.basis,
              style: const TextStyle(fontSize: 12.5, height: 1.4)),
        ],
      ),
    );
  }
}

/// Honest notice when an avoidance could not be respected.
class _UnavoidableCard extends StatelessWidget {
  const _UnavoidableCard({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final names = app.unavoidable
        .map((id) => app.food.ingredients[id]?.name ?? id)
        .join(', ');
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 20, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'We could not fully avoid $names this week — it appears in '
                'essentially every dish we can cook. Everything else you '
                'marked has been kept out.',
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
