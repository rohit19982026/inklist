import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/todo_task.dart';
import 'recurrence_rule.dart';

/// To-do CRUD + day/week/overdue query helpers — mirrors GoalPlannerService's
/// SharedPreferences-backed JSON-list pattern exactly.
class TodoService {
  static const _key = 'todo_tasks_v1';

  // ── CRUD ─────────────────────────────────────────────────────────────────
  static Future<List<TodoTask>> getAll() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => TodoTask.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    } catch (_) {
      return [];
    }
  }

  static Future<void> upsert(TodoTask task) async {
    final p = await SharedPreferences.getInstance();
    final list = await getAll();
    final idx = list.indexWhere((t) => t.id == task.id);
    if (idx >= 0) {
      list[idx] = task;
    } else {
      list.add(task);
    }
    await p.setString(_key, jsonEncode(list.map((t) => t.toJson()).toList()));
  }

  static Future<void> delete(String id) async {
    final p = await SharedPreferences.getInstance();
    final list = await getAll();
    list.removeWhere((t) => t.id == id);
    await p.setString(_key, jsonEncode(list.map((t) => t.toJson()).toList()));
  }

  /// Toggles completion for [day] — flips completedDates for recurring
  /// tasks, isCompleted/completedAt for one-off tasks.
  static Future<void> toggleOccurrence(String id, DateTime day) async {
    final list = await getAll();
    final idx = list.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final t = list[idx];
    if (t.isRecurring) {
      final key = TodoTask.dateKey(day);
      final next = Set<String>.from(t.completedDates);
      if (next.contains(key)) {
        next.remove(key);
      } else {
        next.add(key);
      }
      list[idx] = t.copyWith(completedDates: next);
    } else {
      list[idx] = t.isCompleted
          ? t.copyWith(isCompleted: false, clearCompletedAt: true)
          : t.copyWith(isCompleted: true, completedAt: DateTime.now());
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  // ── Pure query helpers (testable without SharedPreferences) ────────────────

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static List<TodoTask> tasksForDay(List<TodoTask> all, DateTime day) {
    return all.where((t) {
      if (t.isRecurring) return RecurrenceRule.occursOn(t.recurrenceRule, day);
      return _isSameDay(t.dueDate, day);
    }).toList();
  }

  static List<TodoTask> tasksForWeek(List<TodoTask> all, DateTime weekStart) {
    final out = <TodoTask>[];
    for (var i = 0; i < 7; i++) {
      out.addAll(tasksForDay(all, weekStart.add(Duration(days: i))));
    }
    return out;
  }

  /// Non-recurring tasks only, past due and not completed. Recurring tasks
  /// have no single "overdue" concept — they only ever appear in day/week
  /// views, since "overdue daily reminder" is a fuzzy notion best left
  /// unimplemented.
  static List<TodoTask> overdueTasks(List<TodoTask> all, {DateTime? asOf}) {
    final now = asOf ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return all.where((t) {
      if (t.isRecurring || t.isCompleted) return false;
      final due = DateTime(t.dueDate.year, t.dueDate.month, t.dueDate.day);
      return due.isBefore(today);
    }).toList();
  }

  static Future<({List<TodoTask> today, List<TodoTask> overdue})>
      todayAndOverdue() async {
    final all = await getAll();
    final now = DateTime.now();
    return (
      today: tasksForDay(all, now),
      overdue: overdueTasks(all, asOf: now),
    );
  }

  static DateTime startOfWeek(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
}
