/// Household, preferences and app settings.
library;

import 'package:flutter/material.dart';

import '../../models/food.dart';
import '../../state/app_state.dart';
import '../onboarding/onboarding_screen.dart';
import '../widgets.dart';
import 'day_scores.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = app.profile;

    return CustomScrollView(
      slivers: [
        const SliverAppBar(pinned: true, title: Text('Your household')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          sliver: SliverList.list(
            children: [
              const SectionHeader('Your days'),
              DayScoresCard(app: app),
              const SectionHeader('Household'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${p.householdSize} '
                              '${p.householdSize == 1 ? 'person' : 'people'} · '
                              '${p.diet.label}',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _edit(context),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Edit'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final m in p.members)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                m.isPrimary
                                    ? Icons.person
                                    : (m.isChild
                                        ? Icons.child_care
                                        : Icons.person_outline),
                                size: 18,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(m.name,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              Flexible(
                                flex: 2,
                                child: Text(
                                  '${m.age}y · ${m.weightKg.round()}kg · '
                                  '${m.goal.label}',
                                  textAlign: TextAlign.right,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SectionHeader('Days and shopping'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final r in p.dayRules)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.event_repeat,
                                  size: 18, color: scheme.tertiary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${describeDays(r.weekdays)}: '
                                  '${describeAvoided(r, app.food.ingredients, p.diet).toLowerCase()}',
                                  style: const TextStyle(fontSize: 13.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (p.dayRules.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('No days when foods are given up.',
                              style: TextStyle(
                                  fontSize: 13.5,
                                  color: scheme.onSurfaceVariant)),
                        ),
                      Row(
                        children: [
                          Icon(Icons.shopping_bag_outlined,
                              size: 18, color: scheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                                'Shopping for fresh food: '
                                '${p.shopping.label.toLowerCase()}',
                                style: const TextStyle(fontSize: 13.5)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _edit(context),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Change'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SectionHeader('Pantry'),
              Card(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Icon(Icons.kitchen_outlined, color: scheme.primary),
                  title: const Text('Already at home'),
                  subtitle: Text(
                    p.pantry.isEmpty
                        ? 'Tick staples you keep stocked, like salt or atta, '
                            'to leave them off the shopping list.'
                        : '${p.pantry.length} '
                            '${p.pantry.length == 1 ? 'staple' : 'staples'} left '
                            'off the shopping list',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) =>
                        _PantrySheet(app: app, foods: _pantryCandidates()),
                  ),
                ),
              ),
              const SectionHeader('Data'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.phone_android),
                      title: const Text('Everything stays on this phone'),
                      subtitle: const Text(
                          'No account, no servers, nothing uploaded.'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.delete_outline, color: scheme.error),
                      title: Text('Reset everything',
                          style: TextStyle(color: scheme.error)),
                      subtitle:
                          const Text('Clears your profile and current plan.'),
                      onTap: () => _confirmReset(context),
                    ),
                  ],
                ),
              ),
              const SectionHeader('About the numbers'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nutrition values come from the Indian Food '
                        'Composition Tables 2017 (ICMR-NIN) and USDA '
                        'FoodData Central. Requirements follow ICMR-NIN 2020.',
                        style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: scheme.onSurfaceVariant),
                      ),
                      if (app.food.unverified.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          '${app.food.unverified.length} items still use '
                          'estimated values: '
                          '${app.food.unverified.map((i) => i.name).join(', ')}.',
                          style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: scheme.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        'This app gives general nutrition guidance and is not '
                        'medical advice.',
                        style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Ingredient> _pantryCandidates() {
    final list = app.food.ingredients.values
        .where((i) => i.pantryStaple || i.aisle == Aisle.grains)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  void _edit(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OnboardingScreen(
        ingredients: app.food.ingredients,
        initial: app.profile,
        onComplete: (p) {
          app.updateProfile(p);
          Navigator.of(context).pop();
        },
      ),
    ));
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset everything?'),
        content: const Text(
            'Your household details and this week\'s plan will be deleted. '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) await app.resetAll();
  }
}

/// Picking the staples already at home, with a search for the long list.
class _PantrySheet extends StatefulWidget {
  const _PantrySheet({required this.app, required this.foods});
  final AppState app;
  final List<Ingredient> foods;

  @override
  State<_PantrySheet> createState() => _PantrySheetState();
}

class _PantrySheetState extends State<_PantrySheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.app,
      builder: (context, _) {
        final p = widget.app.profile;
        final shown =
            widget.foods.where((i) => matchesSearch(i, _query)).toList();
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
            children: [
              const Text('Already at home',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'Ticked items are left off the shopping list entirely.',
                style: TextStyle(
                    fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              FoodSearchField(
                hint: 'Search — e.g. salt, atta, ghee',
                onChanged: (q) => setState(() => _query = q),
              ),
              const SizedBox(height: 12),
              if (shown.isEmpty)
                NoSearchMatches(_query)
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final ing in shown)
                      FilterChip(
                        label: Text(ing.name,
                            style: const TextStyle(fontSize: 12.5)),
                        selected: p.pantry.contains(ing.id),
                        onSelected: (sel) {
                          final next = {...p.pantry};
                          sel ? next.add(ing.id) : next.remove(ing.id);
                          widget.app.updateProfile(p.copyWith(pantry: next));
                        },
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
