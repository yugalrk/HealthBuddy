/// Bottom-navigation shell holding the four main screens.
library;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'nutrition/nutrition_screen.dart';
import 'plan/plan_screen.dart';
import 'profile/profile_screen.dart';
import 'shopping/shopping_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.app});
  final AppState app;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          PlanScreen(app: app),
          ShoppingScreen(app: app),
          NutritionScreen(app: app),
          ProfileScreen(app: app),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Plan',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_basket_outlined),
            selectedIcon: Icon(Icons.shopping_basket),
            label: 'Shopping',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart),
            label: 'Nutrition',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Household',
          ),
        ],
      ),
    );
  }
}
