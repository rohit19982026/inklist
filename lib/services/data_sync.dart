import 'package:flutter/foundation.dart';

/// Lightweight global "data changed" signal.
///
/// The bottom-nav tabs are kept alive in an [IndexedStack], so each
/// screen's `_load()`/`_init()` only ever runs once, in `initState`.
/// That means after a mutation happens on a *different* tab — a bank
/// statement import, a backup restore, a re-categorize, a manual
/// quick-add, or a live incoming UPI SMS — the Home / Categories /
/// Insights / Transactions tabs would keep showing stale totals until
/// the app is restarted.
///
/// Fix: screens subscribe to [listenable] in `initState` (and unsubscribe
/// in `dispose`) and reload their data when it fires. Anything that
/// inserts/updates/deletes/restores rows in the `transactions` table
/// calls [notifyChanged] afterwards.
class DataSync {
  DataSync._();

  static final ValueNotifier<int> _version = ValueNotifier<int>(0);

  /// Listen to this to know transaction data changed elsewhere in the app.
  static ValueListenable<int> get listenable => _version;

  /// Call after any insert/update/delete/restore/recategorize that changes
  /// the `transactions` table so other tabs reload next time they're shown.
  static void notifyChanged() => _version.value++;
}
