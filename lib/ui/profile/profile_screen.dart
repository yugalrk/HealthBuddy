/// Household, preferences and app settings.
library;

import 'package:flutter/material.dart';

import '../../models/food.dart';
import '../../state/app_state.dart';
import '../onboarding/onboarding_screen.dart';
import '../widgets.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = app.profile;

    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(title: Text('Your household')),
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
                              Expanded(child: Text(m.name)),
                              Text(
                                '${m.age}y · ${m.weightKg.round()}kg · '
                                '${m.goal.label}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SectionHeader('Pantry'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Anything you tick here is dropped from the shopping '
                        'list entirely.',
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
                          for (final ing in _pantryCandidates())
                            FilterChip(
                              label: Text(ing.name,
                                  style: const TextStyle(fontSize: 12)),
                              selected: p.pantry.contains(ing.id),
                              onSelected: (sel) {
                                final next = {...p.pantry};
                                if (sel) {
                                  next.add(ing.id);
                                } else {
                                  next.remove(ing.id);
                                }
                                app.updateProfile(p.copyWith(pantry: next));
                              },
                            ),
                        ],
                      ),
                    ],
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
