import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';
import '../services/groq_service.dart';
import '../services/alarm_scheduler_service.dart';
import '../services/smart_reminder_service.dart';
import '../models/todo_task.dart';

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
  bool _smartRemindersEnabled = false;
  List<TimeOfDayMs> _smartReminderTimes = SmartReminderService.defaultTimes;

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
    ]);
    if (!mounted) return;
    setState(() {
      _aiEnabled = r[0] as bool;
      _groqApiKey = r[1] as String?;
      _canScheduleExactAlarms = r[2] as bool;
      _smartRemindersEnabled = r[3] as bool;
      _smartReminderTimes = r[4] as List<TimeOfDayMs>;
      _loading = false;
    });
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
