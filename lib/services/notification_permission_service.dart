import 'package:permission_handler/permission_handler.dart';

/// Wraps the OS POST_NOTIFICATIONS runtime permission (required on Android
/// 13+ — without it, EVERY notification the app posts is silently dropped:
/// Smart Reminder check-ins, and the full-screen alarm notification that
/// AlarmRingingService now relies on to reliably show over the lock screen).
/// A no-op returning granted on platforms/OS versions that don't need a
/// runtime grant.
class NotificationPermissionService {
  static Future<bool> isGranted() async {
    return (await Permission.notification.status).isGranted;
  }

  static Future<bool> isPermanentlyDenied() async {
    return (await Permission.notification.status).isPermanentlyDenied;
  }

  /// Shows the system permission dialog. Safe to call repeatedly — the OS
  /// only actually prompts once; after a denial this just re-reads status,
  /// and after "don't ask again" it returns denied without prompting.
  static Future<bool> request() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  static Future<void> openSettings() => openAppSettings();
}
