/// The week's shopping list, grouped by aisle.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/shopping_list.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

class ShoppingScreen extends StatelessWidget {
  const ShoppingScreen({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
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
          sliver: SliverToBoxAdapter(
            child: Card(
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
                            style: TextStyle(
                                fontSize: 13, color: scheme.onSurfaceVariant),
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
                          Text('${total == 0 ? 0 : (done / total * 100).round()}%',
                              style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          sliver: SliverList.list(
            children: [
              for (final aisle in list.orderedAisles) ...[
                SectionHeader(aisle.label),
                ...list.toBuy[aisle]!.map((item) => _ItemTile(
                      item: item,
                      checked: checked.contains(item.ingredient.id),
                      onToggle: () => app.toggleChecked(item.ingredient.id),
                    )),
              ],
              if (list.pantryCheck.isNotEmpty) ...[
                const SectionHeader('Check you already have'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Spices and oils used this week. Most households '
                          'already have these, so they are kept off the buy '
                          'list.',
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
            ],
          ),
        ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.checked,
    required this.onToggle,
  });

  final ShoppingItem item;
  final bool checked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final over = item.overageLabel;

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
                  if (over != null)
                    Text(over,
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
