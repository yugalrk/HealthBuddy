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

import '../../models/profile.dart';

abstract class ProfileRepository {
  Future<Profile?> load();
  Future<void> save(Profile profile);
  Future<void> clear();
}

/// The saved week: the seed it was generated from plus the ticked shopping
/// items. The plan itself is regenerated from the seed, which keeps storage
/// tiny and guarantees plan and profile never drift apart.
class SavedWeek {
  const SavedWeek({
    required this.seed,
    required this.generatedAt,
    this.checkedItems = const {},
  });

  final int seed;
  final DateTime generatedAt;
  final Set<String> checkedItems;

  SavedWeek copyWith({Set<String>? checkedItems}) => SavedWeek(
        seed: seed,
        generatedAt: generatedAt,
        checkedItems: checkedItems ?? this.checkedItems,
      );

  Map<String, dynamic> toJson() => {
        'seed': seed,
        'generatedAt': generatedAt.toIso8601String(),
        'checkedItems': checkedItems.toList(),
      };

  static SavedWeek fromJson(Map<String, dynamic> j) => SavedWeek(
        seed: j['seed'] as int,
        generatedAt: DateTime.parse(j['generatedAt'] as String),
        checkedItems: {...(j['checkedItems'] as List? ?? []).cast<String>()},
      );
}

abstract class PlanRepository {
  Future<SavedWeek?> load();
  Future<void> save(SavedWeek week);
  Future<void> clear();
}

const _profileKey = 'healthbuddy.profile.v1';
const _weekKey = 'healthbuddy.week.v1';

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
