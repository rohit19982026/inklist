import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../theme/app_fonts.dart';
import '../widgets/section_header.dart';
import '../services/groq_service.dart';
import '../services/alarm_scheduler_service.dart';
import '../services/smart_reminder_service.dart';
import '../services/notification_permission_service.dart';
import '../services/alarm_tone_service.dart';
import '../services/google_calendar_service.dart';
import '../services/mcp_bridge_service.dart';
import '../models/todo_task.dart';
import 'font_picker_screen.dart';
import 'alarm_tone_picker_screen.dart';

/// InkList settings — AI, alarms, smart reminders, and (stubbed) Premium.
/// All financial settings from the original app have been removed.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  bool _aiEnabled = true;
  String? _groqApiKey;
  bool _canScheduleExactAlarms = true;
  bool _canUseFullScreenIntent = true;
  bool _ignoringBatteryOptimizations = true;
  bool _notificationsGranted = true;
  bool _notificationsPermanentlyDenied = false;
  bool _smartRemindersEnabled = false;
  List<TimeOfDayMs> _smartReminderTimes = SmartReminderService.defaultTimes;
  String _alarmToneTitle = 'Default';
  bool _calendarSyncEnabled = false;
  bool _calendarSignedIn = false;
  String? _calendarEmail;
  bool _mcpBridgeEnabled = false;
  String? _mcpBridgeAddress;
  String _mcpBridgeToken = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Future.wait([
      GroqService.isEnabled(),
      GroqService.getApiKey(),
      AlarmSchedulerService.canScheduleExactAlarms(),
      SmartReminderService.isEnabled(),
      SmartReminderService.getCheckInTimes(),
      NotificationPermissionService.isGranted(),
      NotificationPermissionService.isPermanentlyDenied(),
      AlarmSchedulerService.canUseFullScreenIntent(),
      AlarmSchedulerService.isIgnoringBatteryOptimizations(),
      AlarmToneService.getSelectedTitle(),
      GoogleCalendarService.isSyncEnabled(),
      GoogleCalendarService.isSignedIn(),
      GoogleCalendarService.signedInEmail(),
      MCPBridgeService.isEnabled(),
      MCPBridgeService.localAddress(),
      MCPBridgeService.getToken(),
    ]);
    if (!mounted) return;
    setState(() {
      _aiEnabled = r[0] as bool;
      _groqApiKey = r[1] as String?;
      _canScheduleExactAlarms = r[2] as bool;
      _smartRemindersEnabled = r[3] as bool;
      _smartReminderTimes = r[4] as List<TimeOfDayMs>;
      _notificationsGranted = r[5] as bool;
      _notificationsPermanentlyDenied = r[6] as bool;
      _canUseFullScreenIntent = r[7] as bool;
      _ignoringBatteryOptimizations = r[8] as bool;
      _alarmToneTitle = r[9] as String;
      _calendarSyncEnabled = r[10] as bool;
      _calendarSignedIn = r[11] as bool;
      _calendarEmail = r[12] as String?;
      _mcpBridgeEnabled = r[13] as bool;
      _mcpBridgeAddress = r[14] as String?;
      _mcpBridgeToken = r[15] as String;
      _loading = false;
    });
  }

  Future<void> _toggleMcpBridge(bool v) async {
    setState(() => _mcpBridgeEnabled = v);
    await MCPBridgeService.setEnabled(v);
    _load();
  }

  Future<void> _regenerateMcpToken() async {
    await MCPBridgeService.regenerateToken();
    _load();
    _toast('New token generated — update it in your MCP server config');
  }

  Future<void> _copyMcpToken() async {
    await Clipboard.setData(ClipboardData(text: _mcpBridgeToken));
    _toast('Token copied');
  }

  Future<void> _copyMcpAddress() async {
    final address = _mcpBridgeAddress;
    if (address == null) return;
    await Clipboard.setData(
        ClipboardData(text: 'http://$address:${MCPBridgeService.port}'));
    _toast('Address copied');
  }

  Future<void> _toggleCalendarSync(bool v) async {
    await GoogleCalendarService.setSyncEnabled(v);
    if (v && !_calendarSignedIn) {
      final ok = await GoogleCalendarService.signIn();
      if (!ok) await GoogleCalendarService.setSyncEnabled(false);
    }
    _load();
  }

  Future<void> _connectCalendar() async {
    final ok = await GoogleCalendarService.signIn();
    if (ok) await GoogleCalendarService.setSyncEnabled(true);
    _load();
  }

  Future<void> _disconnectCalendar() async {
    await GoogleCalendarService.setSyncEnabled(false);
    await GoogleCalendarService.signOut();
    _load();
  }

  Future<void> _fixNotificationPermission() async {
    if (_notificationsPermanentlyDenied) {
      await NotificationPermissionService.openSettings();
    } else {
      await NotificationPermissionService.request();
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text('Settings', style: T.title2()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
                children: [
                  // ── Premium (stubbed purchase) ─────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
                    child: GestureDetector(
                      onTap: _openPaywall,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(Radii.xl),
                          boxShadow: AppColors.coloredShadow(AppColors.primary),
                        ),
                        child: Row(children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(Radii.md),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(Icons.workspace_premium_rounded,
                                color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('InkList Pro',
                                    style: T.body(c: Colors.white).copyWith(
                                        fontWeight: FontWeight.w800, fontSize: 16)),
                                const SizedBox(height: 2),
                                Text('Unlimited habits, focus stats, themes & more',
                                    style: T.caption1(
                                        c: Colors.white.withValues(alpha: 0.82))),
                              ])),
                          Icon(Icons.chevron_right_rounded,
                              color: Colors.white.withValues(alpha: 0.7), size: 22),
                        ]),
                      ),
                    ),
                  ),

                  // ── Appearance ─────────────────────────────────────────────
                  const SectionHeader(
                    title: 'Appearance',
                    subtitle: 'Choose the handwriting or font that fits you',
                  ),
                  _settingsGroup([
                    _settingRow(
                      icon: Icons.font_download_rounded,
                      tint: AppColors.accent,
                      title: 'Font',
                      value:
                          '${AppFonts.current().label} · ${AppFonts.current().handwritten ? 'Handwritten' : 'Clean'} — 21 to choose from',
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const FontPickerScreen()),
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // ── Notifications (foundational for alarms + reminders) ────
                  SectionHeader(
                    title: 'Notifications',
                    subtitle: _notificationsGranted
                        ? 'Allowed'
                        : 'Blocked — alarms and reminders can\'t alert you',
                  ),
                  _settingsGroup([
                    _settingRow(
                      icon: _notificationsGranted
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_off_rounded,
                      tint: _notificationsGranted
                          ? AppColors.success
                          : AppColors.danger,
                      title: 'Allow Notifications',
                      value: _notificationsGranted
                          ? 'On · required for task alarms and smart reminders'
                          : 'Off · tap to grant — nothing can alert you without this',
                      onTap: _notificationsGranted ? null : _fixNotificationPermission,
                      trailing: _notificationsGranted
                          ? const Icon(Icons.check_circle_rounded,
                              color: AppColors.success)
                          : null,
                    ),
                    _settingRow(
                      icon: Icons.tune_rounded,
                      tint: AppColors.textMuted,
                      title: 'Notification Channels',
                      value:
                          'If alarms still stay silent, check Task Alarms isn\'t muted here',
                      onTap: NotificationPermissionService.openChannelSettings,
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // ── AI Assistant (Groq) ────────────────────────────────────
                  SectionHeader(
                    title: 'AI Assistant',
                    subtitle: !_aiEnabled
                        ? 'Disabled'
                        : (_groqApiKey?.isNotEmpty == true
                            ? 'Groq API connected'
                            : 'Add your free API key to enable'),
                  ),
                  _settingsGroup([
                    _settingRow(
                      icon: Icons.auto_awesome_rounded,
                      tint: AppColors.accent,
                      title: 'Enable AI Features',
                      value: _aiEnabled
                          ? 'On · weekly planning, task breakdown, daily brief'
                          : 'Off',
                      trailing: Switch.adaptive(
                        value: _aiEnabled,
                        activeThumbColor: AppColors.accent,
                        onChanged: (v) async {
                          setState(() => _aiEnabled = v);
                          await GroqService.setEnabled(v);
                        },
                      ),
                    ),
                    _settingRow(
                      icon: Icons.key_rounded,
                      tint: AppColors.primary,
                      title: 'Groq API Key',
                      value: (_groqApiKey?.isNotEmpty == true)
                          ? '••••••••${_groqApiKey!.length > 4 ? _groqApiKey!.substring(_groqApiKey!.length - 4) : ''}'
                          : 'Not set · get a free key at console.groq.com',
                      onTap: _editGroqKey,
                    ),
                    _settingRow(
                      icon: Icons.wifi_tethering_rounded,
                      tint: AppColors.info,
                      title: 'Test Connection',
                      value: 'Send a test request to Groq',
                      onTap: _testGroqConnection,
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // ── Task Alarms ────────────────────────────────────────────
                  const SectionHeader(
                    title: 'Task Alarms',
                    subtitle: 'Ring like a real alarm clock for scheduled tasks',
                  ),
                  _settingsGroup([
                    if (!_canScheduleExactAlarms)
                      _settingRow(
                        icon: Icons.alarm_rounded,
                        tint: AppColors.warning,
                        title: 'Allow Exact Alarms',
                        value:
                            'Required for task alarms to ring on time — tap to grant',
                        onTap: () async {
                          await AlarmSchedulerService.requestExactAlarmPermission();
                          _load();
                        },
                      ),
                    if (!_canUseFullScreenIntent)
                      _settingRow(
                        icon: Icons.fullscreen_rounded,
                        tint: AppColors.warning,
                        title: 'Allow Full-Screen Alarms',
                        value:
                            'Required for the alarm to pop up over your lock screen — tap to grant',
                        onTap: () async {
                          await AlarmSchedulerService.requestFullScreenIntentPermission();
                          _load();
                        },
                      ),
                    if (!_ignoringBatteryOptimizations)
                      _settingRow(
                        icon: Icons.battery_alert_rounded,
                        tint: AppColors.danger,
                        title: 'Allow Background Activity',
                        value:
                            'Most likely cause of missed alarms — your phone\'s battery saver can silently block them. Tap to exempt InkList.',
                        onTap: () async {
                          await AlarmSchedulerService.requestIgnoreBatteryOptimizations();
                          _load();
                        },
                      ),
                    _settingRow(
                      icon: Icons.music_note_rounded,
                      tint: AppColors.accent,
                      title: 'Alarm & Notification Tone',
                      value: '$_alarmToneTitle · soothing, not a wake-up alarm',
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AlarmTonePickerScreen()),
                        );
                        _load();
                      },
                    ),
                    _settingRow(
                      icon: Icons.do_not_disturb_on_rounded,
                      tint: AppColors.textMuted,
                      title: 'Do Not Disturb Access',
                      value: 'Optional · lets task alarms ring even in DND mode',
                      onTap: () async {
                        await AlarmSchedulerService.requestDndAccess();
                      },
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // ── Smart Reminders ────────────────────────────────────────
                  SectionHeader(
                    title: 'Smart Reminders',
                    subtitle: _smartRemindersEnabled
                        ? 'Checks in ${_smartReminderTimes.length}x/day and decides what needs your attention'
                        : 'Disabled',
                  ),
                  _settingsGroup([
                    _settingRow(
                      icon: Icons.auto_awesome_motion_rounded,
                      tint: AppColors.accent,
                      title: 'Enable Smart Reminders',
                      value: _smartRemindersEnabled
                          ? 'On · nudges you on its own, no need to open the app'
                          : 'Off',
                      trailing: Switch.adaptive(
                        value: _smartRemindersEnabled,
                        activeThumbColor: AppColors.accent,
                        onChanged: (v) async {
                          setState(() => _smartRemindersEnabled = v);
                          await SmartReminderService.setEnabled(v);
                          await SmartReminderService.syncSchedule();
                        },
                      ),
                    ),
                    _settingRow(
                      icon: Icons.schedule_rounded,
                      tint: AppColors.primary,
                      title: 'Check-in Times',
                      value: _smartReminderTimes
                          .map((t) => TimeOfDay(hour: t.hour, minute: t.minute)
                              .format(context))
                          .join(', '),
                      onTap: _editSmartReminderTimes,
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // ── Calendar ─────────────────────────────────────────────
                  SectionHeader(
                    title: 'Calendar',
                    subtitle: !GoogleCalendarService.isConfigured
                        ? 'Needs setup'
                        : _calendarSignedIn
                            ? 'Connected as ${_calendarEmail ?? ''}'
                            : 'Not connected',
                  ),
                  if (!GoogleCalendarService.isConfigured)
                    _settingsGroup([
                      _settingRow(
                        icon: Icons.event_busy_rounded,
                        tint: AppColors.textMuted,
                        title: 'Google Calendar',
                        value:
                            'This build hasn\'t been configured for Calendar sync yet — ask your developer to finish the Google Cloud Console setup.',
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppColors.card,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(Radii.lg)),
                            title: const Text('Calendar sync isn\'t set up yet'),
                            content: Text(
                              'Showing Google Calendar events in InkList needs a '
                              'one-time Google Cloud Console setup that only the '
                              'developer can do (an OAuth client tied to this '
                              'app). Once that\'s done, this section will let you '
                              'connect your account.',
                              style: T.footnote(),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ])
                  else
                    _settingsGroup([
                      _settingRow(
                        icon: Icons.event_available_rounded,
                        tint: AppColors.accent,
                        title: 'Show Google Calendar Events',
                        value: _calendarSyncEnabled
                            ? 'On · shown alongside your tasks in Today and Week'
                            : 'Off',
                        trailing: Switch.adaptive(
                          value: _calendarSyncEnabled,
                          activeThumbColor: AppColors.accent,
                          onChanged: _toggleCalendarSync,
                        ),
                      ),
                      _settingRow(
                        icon: _calendarSignedIn
                            ? Icons.check_circle_rounded
                            : Icons.login_rounded,
                        tint: _calendarSignedIn
                            ? AppColors.success
                            : AppColors.primary,
                        title: _calendarSignedIn
                            ? 'Disconnect Google Account'
                            : 'Connect Google Account',
                        value: _calendarSignedIn
                            ? _calendarEmail ?? 'Connected'
                            : 'Read-only — InkList never edits your calendar',
                        onTap: _calendarSignedIn
                            ? _disconnectCalendar
                            : _connectCalendar,
                      ),
                    ]),

                  const SizedBox(height: 24),

                  // ── Claude Connector (local MCP bridge) ─────────────────
                  SectionHeader(
                    title: 'Claude Connector',
                    subtitle: _mcpBridgeEnabled
                        ? (MCPBridgeService.isRunning
                            ? 'Running · reachable on your Wi-Fi'
                            : 'On, but not reachable right now')
                        : 'Off',
                  ),
                  _settingsGroup([
                    _settingRow(
                      icon: Icons.hub_rounded,
                      tint: AppColors.accent,
                      title: 'Enable Local API for Claude',
                      value: _mcpBridgeEnabled
                          ? 'On · only while InkList is open, same Wi-Fi only'
                          : 'Lets Claude Desktop/Code read and manage tasks over your Wi-Fi',
                      trailing: Switch.adaptive(
                        value: _mcpBridgeEnabled,
                        activeThumbColor: AppColors.accent,
                        onChanged: _toggleMcpBridge,
                      ),
                    ),
                    if (_mcpBridgeEnabled) ...[
                      _settingRow(
                        icon: Icons.wifi_rounded,
                        tint: AppColors.primary,
                        title: 'Address',
                        value: _mcpBridgeAddress != null
                            ? 'http://$_mcpBridgeAddress:${MCPBridgeService.port} · tap to copy'
                            : 'No Wi-Fi connection detected',
                        onTap: _mcpBridgeAddress != null ? _copyMcpAddress : null,
                      ),
                      _settingRow(
                        icon: Icons.key_rounded,
                        tint: AppColors.primary,
                        title: 'Token',
                        value:
                            '${_mcpBridgeToken.substring(0, _mcpBridgeToken.length.clamp(0, 8))}••••••• · tap to copy',
                        onTap: _copyMcpToken,
                      ),
                      _settingRow(
                        icon: Icons.refresh_rounded,
                        tint: AppColors.textMuted,
                        title: 'Regenerate Token',
                        value:
                            'Invalidates the old token — update your MCP server config after',
                        onTap: _regenerateMcpToken,
                      ),
                    ],
                  ]),

                  const SizedBox(height: 32),
                  Center(child: Text('InkList', style: T.caption1())),
                  const SizedBox(height: 4),
                  Center(
                      child: Text('Privacy-first · your tasks stay on your phone',
                          style: T.caption2())),
                ],
              ),
            ),
    );
  }

  // ── Settings group + row ───────────────────────────────────────────────────
  Widget _settingsGroup(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(Radii.xl),
          boxShadow: AppColors.softShadow,
        ),
        child: Column(
            children: children.asMap().entries.expand((e) => [
                  e.value,
                  if (e.key < children.length - 1)
                    const Padding(
                      padding: EdgeInsets.only(left: 60),
                      child: Divider(height: 1, color: AppColors.divider),
                    ),
                ]).toList()),
      ),
    );
  }

  Widget _settingRow({
    required IconData icon,
    required Color tint,
    required String title,
    required String value,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9)),
              alignment: Alignment.center,
              child: Icon(icon, color: tint, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title, style: T.body().copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(value, style: T.footnote()),
                ])),
            trailing ??
                const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
          ]),
        ),
      ),
    );
  }

  // ── Premium (stubbed) ──────────────────────────────────────────────────────
  void _openPaywall() {
    // Phase 8 replaces this with the real paywall screen + gating.
    _toast('InkList Pro — coming soon');
  }

  // ── AI Assistant dialogs ───────────────────────────────────────────────────
  Future<void> _editGroqKey() async {
    final ctrl = TextEditingController(text: _groqApiKey ?? '');
    var obscure = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
          title: const Text('Groq API Key'),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Get a free key: console.groq.com/keys',
                    style: T.footnote(c: AppColors.textSecondary)),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscure
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded),
                      onPressed: () =>
                          setDialogState(() => obscure = !obscure),
                    ),
                  ),
                ),
              ]),
          actions: [
            if (_groqApiKey?.isNotEmpty == true)
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Clear',
                    style: TextStyle(color: AppColors.danger)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == null) {
      await GroqService.clearApiKey();
      if (!mounted) return;
      setState(() => _groqApiKey = null);
      _toast('API key removed');
      return;
    }
    if (ok != true) return;
    final key = ctrl.text.trim();
    if (key.isEmpty) return;
    await GroqService.setApiKey(key);
    if (!mounted) return;
    setState(() => _groqApiKey = key);
    _toast('Groq API key saved');
  }

  Future<void> _testGroqConnection() async {
    if (_groqApiKey?.isNotEmpty != true) {
      _toast('Add your Groq API key first');
      return;
    }
    _toast('Testing…');
    final result = await GroqService.testConnection();
    if (!mounted) return;
    _toast(result.isSuccess
        ? 'Connected to Groq ✓'
        : (result.error ?? 'Connection failed'));
  }

  // ── Smart Reminders dialog ─────────────────────────────────────────────────
  Future<void> _editSmartReminderTimes() async {
    var times = List<TimeOfDayMs>.from(_smartReminderTimes);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
          title: const Text('Check-in Times'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('InkList checks your tasks and decides what needs attention.',
                  style: T.footnote()),
              const SizedBox(height: 10),
              ...List.generate(times.length, (i) {
                final t = times[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_rounded,
                      color: AppColors.primary),
                  title: Text(
                      TimeOfDay(hour: t.hour, minute: t.minute).format(ctx)),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay(hour: t.hour, minute: t.minute),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        times[i] = TimeOfDayMs(
                            hour: picked.hour, minute: picked.minute);
                      });
                    }
                  },
                );
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await SmartReminderService.setCheckInTimes(times);
    await SmartReminderService.syncSchedule();
    if (!mounted) return;
    setState(() => _smartReminderTimes = times);
    _toast('Check-in times updated');
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: T.footnote(c: Colors.white)),
        backgroundColor: AppColors.textPrimary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md)),
      ));
}
