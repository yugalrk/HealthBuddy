/// The week's shopping list.
///
/// The point of this screen is not the meal plan — it is making sure the
/// kitchen holds the materials needed to cook a balanced week. You can cook
/// whatever you like from it; the plan is one worked example of how these
/// ingredients add up to the household's nutrient targets.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/shopping_list.dart';
import '../../models/food.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';

enum _GroupMode { aisle, nutrition }

class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key, required this.app});
  final AppState app;

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  _GroupMode _mode = _GroupMode.aisle;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final list = app.shoppingList;
    final scheme = Theme.of(context).colorScheme;
    if (list == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final checked = app.checkedItems;
    final total = list.itemCount;
    final done = list.toBuy.values
        .expand((e) => e)
        .where((i) => checked.contains(i.ingredient.id))
        .length;

    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: const Text('Shopping list'),
          actions: [
            IconButton(
              tooltip: 'Copy list',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () async {
                await Clipboard.setData(
                    ClipboardData(text: list.toShareText()));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Shopping list copied')),
                  );
                }
              },
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          sliver: SliverList.list(children: [
            _ProgressCard(done: done, total: total, app: app),
            const SizedBox(height: 12),
            _CoverageCard(list: list, app: app),
            const SizedBox(height: 16),
            SegmentedButton<_GroupMode>(
              segments: const [
                ButtonSegment(
                  value: _GroupMode.aisle,
                  label: Text('By aisle'),
                  icon: Icon(Icons.storefront_outlined, size: 18),
                ),
                ButtonSegment(
                  value: _GroupMode.nutrition,
                  label: Text('By nutrition'),
                  icon: Icon(Icons.eco_outlined, size: 18),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
          ]),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          sliver: SliverList.list(
            children: _mode == _GroupMode.aisle
                ? _aisleSections(list, checked, scheme)
                : _nutritionSections(list, checked, scheme),
          ),
        ),
      ],
    );
  }

  List<Widget> _aisleSections(
      ShoppingList list, Set<String> checked, ColorScheme scheme) {
    return [
      for (final aisle in list.orderedAisles) ...[
        SectionHeader(aisle.label),
        ...list.toBuy[aisle]!.map((item) => _ItemTile(
              item: item,
              checked: checked.contains(item.ingredient.id),
              onToggle: () => widget.app.toggleChecked(item.ingredient.id),
            )),
      ],
      if (list.pantryCheck.isNotEmpty) _pantryCard(list, scheme),
    ];
  }

  List<Widget> _nutritionSections(
      ShoppingList list, Set<String> checked, ColorScheme scheme) {
    final grouped = list.byNutrientRole;
    return [
      for (final role in list.orderedRoles) ...[
        SectionHeader(role.label),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            role.why,
            style: TextStyle(
                fontSize: 12.5, height: 1.35, color: scheme.onSurfaceVariant),
          ),
        ),
        _RoleTotals(items: grouped[role]!),
        ...grouped[role]!.map((item) => _ItemTile(
              item: item,
              checked: checked.contains(item.ingredient.id),
              onToggle: () => widget.app.toggleChecked(item.ingredient.id),
              showProtein: role == NutrientRole.protein,
            )),
      ],
    ];
  }

  Widget _pantryCard(ShoppingList list, ColorScheme scheme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('Check you already have'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Spices and oils used this week. Most households already '
                    'have these, so they are kept off the buy list.',
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final i in list.pantryCheck)
                        Chip(
                          label: Text(i.ingredient.name,
                              style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard(
      {required this.done, required this.total, required this.app});
  final int done;
  final int total;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$done of $total items',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    'One week for ${app.profile.householdSize} '
                    '${app.profile.householdSize == 1 ? 'person' : 'people'}',
                    style:
                        TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 46,
              height: 46,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: total == 0 ? 0 : done / total,
                    strokeWidth: 5,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                  Text(
                      '${total == 0 ? 0 : (done / total * 100).round()}%',
                      style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Answers the real question: does this basket hold enough to cook a balanced
/// week, whatever you actually choose to cook from it?
class _CoverageCard extends StatelessWidget {
  const _CoverageCard({required this.list, required this.app});
  final ShoppingList list;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final need = app.weeklyTargets;
    final cover = list.coverageAgainst(need);
    final provides = list.provides;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('What this basket covers',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Cook whatever you like from these ingredients — this is what '
              'they add up to against your household\'s week.',
              style: TextStyle(
                  fontSize: 12.5, height: 1.35, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            _CoverRow(
                label: 'Protein',
                ratio: cover.protein,
                got: provides.protein,
                need: need.protein,
                unit: 'g'),
            _CoverRow(
                label: 'Energy',
                ratio: cover.kcal,
                got: provides.kcal,
                need: need.kcal,
                unit: 'kcal'),
            _CoverRow(
                label: 'Fibre',
                ratio: cover.fibre,
                got: provides.fibre,
                need: need.fibre,
                unit: 'g'),
            _CoverRow(
                label: 'Iron',
                ratio: cover.iron,
                got: provides.iron,
                need: need.iron,
                unit: 'mg'),
            _CoverRow(
                label: 'Calcium',
                ratio: cover.calcium,
                got: provides.calcium,
                need: need.calcium,
                unit: 'mg'),
            const SizedBox(height: 12),
            _CerealProteinNote(share: list.cerealProteinShare),
          ],
        ),
      ),
    );
  }
}

/// How much of the week's protein is cereal protein.
///
/// Surfaced because it is both surprising and actionable: in a typical Indian
/// vegetarian basket, roti and rice supply about as much protein as the dals
/// do, and cereal protein is less digestible. If this share is high, the fix
/// is more dal, paneer, soya or curd — not more roti.
class _CerealProteinNote extends StatelessWidget {
  const _CerealProteinNote({required this.share});
  final double share;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = (share * 100).round();
    final high = share > 0.45;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(high ? Icons.info_outline : Icons.check_circle_outline,
              size: 18, color: high ? const Color(0xFFE08A00) : scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              high
                  ? '$pct% of this week\'s protein comes from grains. Cereal '
                      'protein is less well absorbed, so leaning more on dal, '
                      'paneer, soya or curd would go further than extra roti.'
                  : '$pct% of this week\'s protein comes from grains, with the '
                      'rest from dals, dairy and soya — a good balance for a '
                      'vegetarian week.',
              style: TextStyle(
                  fontSize: 12, height: 1.4, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverRow extends StatelessWidget {
  const _CoverRow({
    required this.label,
    required this.ratio,
    required this.got,
    required this.need,
    required this.unit,
  });
  final String label;
  final double ratio;
  final double got;
  final double need;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = nutrientStatusColor(scheme, ratio);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            child: Text(label, style: const TextStyle(fontSize: 13.5)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Stack(children: [
                Container(height: 7, color: scheme.surfaceContainerHighest),
                FractionallySizedBox(
                  widthFactor: ratio.clamp(0.0, 1.0).toDouble(),
                  child: Container(height: 7, color: color),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Text(
              '${got.round()} / ${need.round()} $unit',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Per-group totals, so "Protein foods" says how much protein it is actually
/// buying rather than just listing packets.
class _RoleTotals extends StatelessWidget {
  const _RoleTotals({required this.items});
  final List<ShoppingItem> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var n = const Nutrients();
    for (final i in items) {
      n += i.contribution;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 12,
        children: [
          for (final (label, value, unit) in [
            ('protein', n.protein, 'g'),
            ('energy', n.kcal, 'kcal'),
            ('iron', n.iron, 'mg'),
            ('calcium', n.calcium, 'mg'),
          ])
            if (value >= 1)
              Text('${value.round()} $unit $label',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary)),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.checked,
    required this.onToggle,
    this.showProtein = false,
  });

  final ShoppingItem item;
  final bool checked;
  final VoidCallback onToggle;
  final bool showProtein;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final over = item.overageLabel;
    final sub = showProtein
        ? '${item.contribution.protein.round()} g protein'
            '${over == null ? '' : ' · $over'}'
        : over;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Checkbox(value: checked, onChanged: (_) => onToggle()),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.ingredient.name,
                    style: TextStyle(
                      fontSize: 15,
                      decoration: checked ? TextDecoration.lineThrough : null,
                      color: checked ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                  if (sub != null)
                    Text(sub,
                        style: TextStyle(
                            fontSize: 11.5, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Text(
              item.quantityLabel,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: checked ? scheme.onSurfaceVariant : scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
