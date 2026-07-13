import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lightweight global "data changed" signal.
///
/// The bottom-nav tabs are kept alive in an [IndexedStack], so each screen's
/// `_load()`/`_init()` only ever runs once, in `initState`. That means after
/// a mutation happens on a *different* tab — adding a task from Week while
/// Today is also mounted, an AI-generated weekly plan, a habit check-in —
/// the other tabs would keep showing stale data until the app restarts.
///
/// Fix: screens subscribe to [listenable] in `initState` (and unsubscribe in
/// `dispose`) and reload their data when it fires. Anything that
/// inserts/updates/deletes/toggles a task or habit calls [notifyChanged]
/// afterwards.
class DataSync {
  DataSync._();

  static const _methods = MethodChannel('com.rohit.inklist/methods');
  static final ValueNotifier<int> _version = ValueNotifier<int>(0);

  /// Listen to this to know task/habit data changed elsewhere in the app.
  static ValueListenable<int> get listenable => _version;

  /// Call after any insert/update/delete/toggle that changes tasks or habits
  /// so other tabs reload next time they're shown. Also refreshes the
  /// home-screen widget — best-effort, since the widget also refreshes on
  /// its own periodic cycle regardless.
  static void notifyChanged() {
    _version.value++;
    _methods.invokeMethod('updateWidget').catchError((_) => null);
  }
}
