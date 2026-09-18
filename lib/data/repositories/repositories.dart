/// Persistence seam.
///
/// The app is local-first: everything lives on the device. These interfaces
/// exist so a syncing implementation can be dropped in later without touching
/// the UI or the engine — [SharedPrefsProfileRepository] is simply the local
/// one.
///
/// The stored payloads are small (a profile, one week plan, a set of ticked
/// shopping items) and are never queried, only read and written whole, so JSON
/// in shared_preferences is the right tool. A SQL layer would add codegen and
/// migrations to buy nothing.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../engine/day_score.dart';
import '../../models/profile.dart';

abstract class ProfileRepository {
  Future<Profile?> load();
  Future<void> save(Profile profile);
  Future<void> clear();
}

/// The saved week.
///
/// Once a week is under way it is adjusted to what the household actually
/// ate, so the plan is stored as it stands rather than regenerated from its
/// seed. [plan] holds that, alongside the end-of-day feedback, the shops
/// already made, and the ticked shopping items. A week saved before plans
/// were stored has no [plan], and is regenerated from [seed].
class SavedWeek {
  const SavedWeek({
    required this.seed,
    required this.generatedAt,
    this.checkedItems = const {},
    this.plan,
    this.feedback = const [],
    this.bought = const [],
    this.frozenThrough = -1,
  });

  final int seed;

  /// When the week was planned. Its date is day 0 of the week.
  final DateTime generatedAt;
  final Set<String> checkedItems;
  final Map<String, dynamic>? plan;
  final List<Map<String, dynamic>> feedback;
  final List<Map<String, dynamic>> bought;
  final int frozenThrough;

  SavedWeek copyWith({
    Set<String>? checkedItems,
    Map<String, dynamic>? plan,
    List<Map<String, dynamic>>? feedback,
    List<Map<String, dynamic>>? bought,
    int? frozenThrough,
  }) =>
      SavedWeek(
        seed: seed,
        generatedAt: generatedAt,
        checkedItems: checkedItems ?? this.checkedItems,
        plan: plan ?? this.plan,
        feedback: feedback ?? this.feedback,
        bought: bought ?? this.bought,
        frozenThrough: frozenThrough ?? this.frozenThrough,
      );

  Map<String, dynamic> toJson() => {
        'seed': seed,
        'generatedAt': generatedAt.toIso8601String(),
        'checkedItems': checkedItems.toList(),
        if (plan != null) 'plan': plan,
        'feedback': feedback,
        'bought': bought,
        'frozenThrough': frozenThrough,
      };

  static SavedWeek fromJson(Map<String, dynamic> j) => SavedWeek(
        seed: j['seed'] as int,
        generatedAt: DateTime.parse(j['generatedAt'] as String),
        checkedItems: {...(j['checkedItems'] as List? ?? []).cast<String>()},
        plan: j['plan'] as Map<String, dynamic>?,
        feedback: [
          for (final f in (j['feedback'] as List? ?? []))
            f as Map<String, dynamic>
        ],
        bought: [
          for (final b in (j['bought'] as List? ?? []))
            b as Map<String, dynamic>
        ],
        frozenThrough: j['frozenThrough'] as int? ?? -1,
      );
}

abstract class PlanRepository {
  Future<SavedWeek?> load();
  Future<void> save(SavedWeek week);
  Future<void> clear();
}

/// Scored days. Kept apart from the week, which is replaced every seven
/// days, so the history outlives it.
abstract class ScoreRepository {
  Future<ScoreLog> load();
  Future<void> save(ScoreLog log);
  Future<void> clear();
}

const _profileKey = 'healthbuddy.profile.v1';
const _weekKey = 'healthbuddy.week.v1';
const _scoresKey = 'healthbuddy.scores.v1';

class SharedPrefsProfileRepository implements ProfileRepository {
  @override
  Future<Profile?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileKey);
    if (raw == null) return null;
    try {
      return Profile.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      // A profile we cannot parse is worse than none: fall back to onboarding
      // rather than crashing on every launch.
      await prefs.remove(_profileKey);
      return null;
    }
  }

  @override
  Future<void> save(Profile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, json.encode(profile.toJson()));
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileKey);
  }
}

class SharedPrefsPlanRepository implements PlanRepository {
  @override
  Future<SavedWeek?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_weekKey);
    if (raw == null) return null;
    try {
      return SavedWeek.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      await prefs.remove(_weekKey);
      return null;
    }
  }

  @override
  Future<void> save(SavedWeek week) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_weekKey, json.encode(week.toJson()));
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_weekKey);
  }
}

class SharedPrefsScoreRepository implements ScoreRepository {
  @override
  Future<ScoreLog> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scoresKey);
    if (raw == null) return ScoreLog();
    try {
      return ScoreLog.fromJson(json.decode(raw) as List<dynamic>);
    } catch (_) {
      await prefs.remove(_scoresKey);
      return ScoreLog();
    }
  }

  @override
  Future<void> save(ScoreLog log) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scoresKey, json.encode(log.toJson()));
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_scoresKey);
  }
}
