import 'package:flutter/material.dart';

import 'state/app_state.dart';
import 'ui/home_shell.dart';
import 'ui/onboarding/onboarding_screen.dart';
import 'ui/theme.dart';

void main() {
  runApp(const HealthBuddyApp());
}

class HealthBuddyApp extends StatefulWidget {
  const HealthBuddyApp({super.key});

  @override
  State<HealthBuddyApp> createState() => _HealthBuddyAppState();
}

class _HealthBuddyAppState extends State<HealthBuddyApp> {
  final _app = AppState();

  @override
  void initState() {
    super.initState();
    _app.init();
  }

  @override
  void dispose() {
    _app.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HealthBuddy',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: ListenableBuilder(
        listenable: _app,
        builder: (context, _) {
          switch (_app.state) {
            case LoadState.loading:
              return const _Splash();
            case LoadState.onboarding:
              return OnboardingScreen(
                ingredients: _app.food.ingredients,
                onComplete: _app.completeOnboarding,
              );
            case LoadState.ready:
              if (_app.generating && _app.plan == null) {
                return const _Splash(message: 'Planning your week…');
              }
              return HomeShell(app: _app);
          }
        },
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_menu, size: 48, color: scheme.primary),
            const SizedBox(height: 20),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            if (message != null) ...[
              const SizedBox(height: 20),
              Text(message!, style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}
