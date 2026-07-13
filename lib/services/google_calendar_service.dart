import 'dart:async';
import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/calendar_event.dart';

/// Read-only Google Calendar import: shows the user's calendar events
/// alongside InkList tasks. InkList never writes to the calendar.
///
/// Requires a Google Cloud Console OAuth Web client ID (see [_serverClientId]
/// below) that only the app owner can create — see the Settings screen's
/// Calendar section, which explains this to the user when it's unconfigured.
/// Every method degrades gracefully when unconfigured, signed out, or the
/// network call fails: an enhancement layered on top of the task list, same
/// contract as [GroqService].
class GoogleCalendarService {
  GoogleCalendarService._();

  /// Fill in with the "Web application" type OAuth 2.0 client ID from
  /// Google Cloud Console (NOT the Android client ID — google_sign_in needs
  /// this specific type for its `serverClientId`, even for a purely Android
  /// app; see the Calendar setup steps for exactly how to create both). This
  /// value is not secret — Google's Android OAuth clients have no client
  /// secret, and the server client ID is just an audience identifier.
  static const _serverClientId = '';

  static const _scopes = ['https://www.googleapis.com/auth/calendar.readonly'];
  static const _syncEnabledKey = 'calendar_sync_enabled';

  static bool get isConfigured => _serverClientId.isNotEmpty;

  static bool _initialized = false;
  static GoogleSignInAccount? _account;

  static Future<void> _ensureInitialized() async {
    if (_initialized || !isConfigured) return;
    _initialized = true;
    await GoogleSignIn.instance.initialize(serverClientId: _serverClientId);
    GoogleSignIn.instance.authenticationEvents.listen((event) {
      _account = switch (event) {
        GoogleSignInAuthenticationEventSignIn() => event.user,
        GoogleSignInAuthenticationEventSignOut() => null,
      };
    });
    final lightweight = GoogleSignIn.instance.attemptLightweightAuthentication();
    if (lightweight != null) {
      try {
        final account = await lightweight;
        if (account != null) _account = account;
      } catch (_) {}
    }
  }

  static Future<bool> isSignedIn() async {
    await _ensureInitialized();
    return _account != null;
  }

  static Future<String?> signedInEmail() async {
    await _ensureInitialized();
    return _account?.email;
  }

  /// Starts the interactive sign-in flow and immediately requests the
  /// Calendar scope. Must be called from a user interaction (a button tap).
  static Future<bool> signIn() async {
    if (!isConfigured) return false;
    await _ensureInitialized();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      await account.authorizationClient.authorizeScopes(_scopes);
      _account = account;
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> signOut() async {
    if (!isConfigured) return;
    await _ensureInitialized();
    await GoogleSignIn.instance.disconnect();
    _account = null;
  }

  static Future<bool> isSyncEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_syncEnabledKey) ?? false;
  }

  static Future<void> setSyncEnabled(bool enabled) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_syncEnabledKey, enabled);
  }

  /// Empty list whenever the feature isn't usable yet (unconfigured, sync
  /// disabled, signed out) or the request fails for any reason — this never
  /// blocks the Today/Week screens that call it.
  static Future<List<CalendarEvent>> fetchEventsForRange(
    DateTime start,
    DateTime end,
  ) async {
    if (!isConfigured || !await isSyncEnabled()) return [];
    await _ensureInitialized();
    final account = _account;
    if (account == null) return [];
    try {
      final headers = await account.authorizationClient
          .authorizationHeaders(_scopes, promptIfNecessary: false)
          .timeout(const Duration(seconds: 10));
      if (headers == null) return [];
      final uri = Uri.parse(
        'https://www.googleapis.com/calendar/v3/calendars/primary/events',
      ).replace(queryParameters: {
        'timeMin': start.toUtc().toIso8601String(),
        'timeMax': end.toUtc().toIso8601String(),
        'singleEvents': 'true',
        'orderBy': 'startTime',
      });
      final resp =
          await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return [];
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final items = (decoded['items'] as List?) ?? const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(CalendarEvent.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
