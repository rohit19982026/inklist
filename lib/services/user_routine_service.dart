import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_routine.dart';

/// Persistence for [UserRoutine] — a single small JSON blob, same pattern
/// as every other lightweight settings value in this app.
class UserRoutineService {
  UserRoutineService._();

  static const _key = 'user_routine_v1';

  static Future<UserRoutine> getRoutine() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return const UserRoutine();
    try {
      return UserRoutine.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const UserRoutine();
    }
  }

  static Future<void> setRoutine(UserRoutine routine) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(routine.toJson()));
  }
}
