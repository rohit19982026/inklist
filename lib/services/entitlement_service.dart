import 'package:shared_preferences/shared_preferences.dart';

/// Free vs Pro entitlement. v1 has no real billing (the paywall purchase is
/// stubbed, landing fully in Phase 8), so this reads a local `is_pro` flag
/// that defaults to false. Feature gates across the app funnel through
/// [isPro] so flipping this one place unlocks everything later.
class EntitlementService {
  static const _key = 'is_pro';

  /// Free tier caps the habit tracker to keep Pro's "unlimited habits" a
  /// real upgrade reason.
  static const maxFreeHabits = 3;

  static Future<bool> isPro() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_key) ?? false;
  }

  /// Debug/QA + (later) the real purchase flow flips this.
  static Future<void> setPro(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, value);
  }
}
