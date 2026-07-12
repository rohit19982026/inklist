import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/habit.dart';

/// Habit CRUD + completion toggling, backed by a single JSON list in
/// SharedPreferences (`habits_v1`) — same pattern as TodoService.
class HabitService {
  static const _key = 'habits_v1';

  static Future<List<Habit>> getAll() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Habit.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveAll(List<Habit> habits) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(habits.map((h) => h.toJson()).toList()));
  }

  static Future<void> upsert(Habit habit) async {
    final list = await getAll();
    final idx = list.indexWhere((h) => h.id == habit.id);
    if (idx >= 0) {
      list[idx] = habit;
    } else {
      list.add(habit);
    }
    await _saveAll(list);
  }

  static Future<void> delete(String id) async {
    final list = await getAll();
    list.removeWhere((h) => h.id == id);
    await _saveAll(list);
  }

  /// Flip completion for [day] on the given habit.
  static Future<void> toggle(String id, DateTime day) async {
    final list = await getAll();
    final idx = list.indexWhere((h) => h.id == id);
    if (idx < 0) return;
    final h = list[idx];
    final key = Habit.dateKey(day);
    final next = Set<String>.from(h.completedDates);
    if (next.contains(key)) {
      next.remove(key);
    } else {
      next.add(key);
    }
    list[idx] = h.copyWith(completedDates: next);
    await _saveAll(list);
  }
}
