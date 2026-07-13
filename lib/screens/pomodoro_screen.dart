import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../models/todo_task.dart';
import '../models/pomodoro.dart';
import '../models/focus_suggestion.dart';
import '../services/todo_service.dart';
import '../services/data_sync.dart';
import '../services/groq_service.dart';
import '../services/pomodoro_service.dart';
import '../services/alarm_scheduler_service.dart';
import '../services/behavior_insights_service.dart';
import '../services/habit_service.dart';
import '../widgets/ink_widgets.dart';
import '../widgets/focus_celebration_overlay.dart';

/// InkList "Focus" — a Pomodoro timer. Classic 25/5/15 cycles with a long
/// break every N rounds, an optional bound task, an AI focus coach, and a
/// sessions-today count. The countdown is Dart-driven; a native alarm is
/// scheduled at the running phase's end so the user is still chimed if the
/// app is backgrounded, and the timer snapshot is persisted so it survives a
/// process kill.
class PomodoroScreen extends StatefulWidget {
  const PomodoroScreen({super.key});
  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen>
    with WidgetsBindingObserver {
  PomodoroConfig _config = PomodoroConfig.classic;
  PomodoroPhase _phase = PomodoroPhase.work;
  Duration _remaining = const Duration(minutes: 25);
  bool _running = false;
  int _completedWorkRounds = 0;
  String? _boundTaskTitle;

  int _sessionsToday = 0;
  int _minutesToday = 0;

  List<TodoTask> _openTasks = const [];
  bool _aiConfigured = false;
  bool _coaching = false;

  Timer? _ticker;
  DateTime? _endsAt;
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DataSync.listenable.addListener(_loadTasks);
    _bootstrap();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    DataSync.listenable.removeListener(_loadTasks);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !_restoring) {
      _syncFromClock();
      _refreshSummary();
    }
  }

  Color get _phaseColor => switch (_phase) {
        PomodoroPhase.work => AppColors.primary,
        PomodoroPhase.shortBreak => AppColors.mint,
        PomodoroPhase.longBreak => AppColors.accent,
      };

  int get _totalSeconds => _config.minutesFor(_phase) * 60;

  // ── Bootstrap / restore ─────────────────────────────────────────────────
  Future<void> _bootstrap() async {
    _config = await PomodoroService.getConfig();
    final active = await PomodoroService.getActive();
    await _loadTasks();
    await _refreshSummary();

    if (active != null) {
      _phase = active.phase;
      _completedWorkRounds = active.completedWorkRounds;
      _boundTaskTitle = active.taskTitle;
      if (active.running) {
        final endsAt = DateTime.fromMillisecondsSinceEpoch(active.endsAtMillis);
        final left = endsAt.difference(DateTime.now());
        if (left.inSeconds > 0) {
          _endsAt = endsAt;
          _remaining = left;
          _running = true;
          _startTicker();
          // Re-assert the native chime (same request code overwrites).
          AlarmSchedulerService.schedulePomodoroChime(
              endsAt, '${_phase.label} done');
        } else {
          // Phase finished while the app was away.
          await _handleCompletion(silent: true);
        }
      } else {
        _remaining = Duration(seconds: active.remainingSeconds);
      }
    } else {
      _remaining = Duration(seconds: _totalSeconds);
    }
    if (mounted) setState(() => _restoring = false);
  }

  Future<void> _loadTasks() async {
    final all = await TodoService.getAll();
    final now = DateTime.now();
    final open = TodoService.tasksForDay(all, now)
        .where((t) => !t.isCompletedOn(now))
        .toList();
    final configured = await GroqService.isConfigured;
    if (!mounted) return;
    setState(() {
      _openTasks = open;
      _aiConfigured = configured;
    });
  }

  Future<void> _refreshSummary() async {
    final s = await PomodoroService.summaryFor();
    if (!mounted) return;
    setState(() {
      _sessionsToday = s.count;
      _minutesToday = s.minutes;
    });
  }

  // ── Timer control ───────────────────────────────────────────────────────
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _syncFromClock());
  }

  void _syncFromClock() {
    if (!_running || _endsAt == null) return;
    final left = _endsAt!.difference(DateTime.now());
    if (left.inSeconds <= 0) {
      _handleCompletion();
    } else {
      setState(() => _remaining = left);
    }
  }

  Future<void> _persistActive() async {
    await PomodoroService.saveActive(ActiveTimer(
      phase: _phase,
      running: _running,
      endsAtMillis: _endsAt?.millisecondsSinceEpoch ?? 0,
      remainingSeconds: _remaining.inSeconds,
      completedWorkRounds: _completedWorkRounds,
      taskTitle: _boundTaskTitle,
    ));
  }

  Future<void> _start() async {
    HapticFeedback.mediumImpact();
    _endsAt = DateTime.now().add(_remaining);
    setState(() => _running = true);
    _startTicker();
    await AlarmSchedulerService.schedulePomodoroChime(
        _endsAt!, '${_phase.label} done');
    await _persistActive();
  }

  Future<void> _pause() async {
    HapticFeedback.lightImpact();
    _ticker?.cancel();
    // Freeze remaining from the clock so nothing drifts.
    if (_endsAt != null) {
      final left = _endsAt!.difference(DateTime.now());
      _remaining = left.inSeconds > 0 ? left : Duration.zero;
    }
    _endsAt = null;
    setState(() => _running = false);
    await AlarmSchedulerService.cancelPomodoroChime();
    await _persistActive();
  }

  Future<void> _reset() async {
    HapticFeedback.lightImpact();
    _ticker?.cancel();
    _endsAt = null;
    setState(() {
      _running = false;
      _remaining = Duration(seconds: _totalSeconds);
    });
    await AlarmSchedulerService.cancelPomodoroChime();
    await PomodoroService.clearActive();
  }

  /// Advance to the next phase without completing the current one.
  Future<void> _skip() async {
    HapticFeedback.selectionClick();
    _ticker?.cancel();
    _endsAt = null;
    await AlarmSchedulerService.cancelPomodoroChime();
    _advancePhase(countWork: false);
    setState(() {
      _running = false;
      _remaining = Duration(seconds: _totalSeconds);
    });
    await PomodoroService.clearActive();
  }

  /// The running phase reached zero.
  Future<void> _handleCompletion({bool silent = false}) async {
    _ticker?.cancel();
    _endsAt = null;
    _running = false;
    await AlarmSchedulerService.cancelPomodoroChime();

    final finishedPhase = _phase;
    if (finishedPhase == PomodoroPhase.work) {
      await PomodoroService.logSession(PomodoroSession(
        completedAt: DateTime.now(),
        minutes: _config.workMinutes,
        taskTitle: _boundTaskTitle,
      ));
    }
    if (!silent) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
    }
    _advancePhase(countWork: true);
    _remaining = Duration(seconds: _totalSeconds);
    await PomodoroService.clearActive();
    await _refreshSummary();
    if (mounted) {
      setState(() {});
      if (!silent) {
        // A completed work session gets the celebration overlay instead of
        // the plain banner — break completions keep the low-key banner.
        if (finishedPhase == PomodoroPhase.work) {
          _celebrateFocusSession();
        } else {
          _showPhaseBanner(finishedPhase);
        }
      }
    }
  }

  /// Shows the celebration overlay immediately with an instant local
  /// message, then swaps in an AI-generated one if it arrives in time — the
  /// celebration itself never waits on the network.
  void _celebrateFocusSession() {
    FocusCelebrationOverlay.show(
      context,
      message: FocusCelebrationOverlay.randomLocalMessage(),
      betterMessage: _fetchCelebrationMessage(),
    );
  }

  Future<String?> _fetchCelebrationMessage() async {
    if (!_aiConfigured) return null;
    final all = await TodoService.getAll();
    final habits = await HabitService.getAll();
    final sessions = await PomodoroService.getSessions();
    final behaviorContext = BehaviorInsightsService.summarize(
      tasks: all,
      habits: habits,
      sessions: sessions,
    );
    final result = await GroqService.pomodoroCelebrationMessage(
      taskTitle: _boundTaskTitle ?? '',
      completedRoundsToday: _sessionsToday,
      behaviorContext: behaviorContext,
    );
    return result.isSuccess ? result.data : null;
  }

  /// Move [_phase] to whatever should come next. When [countWork] and we just
  /// finished a work phase, bump the round count first so the long-break
  /// cadence is correct.
  void _advancePhase({required bool countWork}) {
    if (_phase == PomodoroPhase.work) {
      if (countWork) _completedWorkRounds++;
      _phase = _config.breakAfter(_completedWorkRounds);
    } else {
      _phase = PomodoroPhase.work;
    }
  }

  void _showPhaseBanner(PomodoroPhase finished) {
    final msg = finished == PomodoroPhase.work
        ? 'Focus done — time for a ${_phase.label.toLowerCase()} 🌿'
        : 'Break over — ready to focus? ✍️';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: T.footnote(c: Colors.white)),
      backgroundColor: AppColors.textPrimary,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
    ));
  }

  // ── Bound task + AI coach ───────────────────────────────────────────────
  Future<void> _pickTask() async {
    HapticFeedback.selectionClick();
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _TaskPickerSheet(
        tasks: _openTasks,
        current: _boundTaskTitle,
      ),
    );
    if (selected == null) return;
    setState(() => _boundTaskTitle = selected.isEmpty ? null : selected);
    if (_running || _remaining.inSeconds != _totalSeconds) _persistActive();
  }

  Future<void> _askCoach() async {
    if (_coaching) return;
    if (!_aiConfigured) {
      _pickTask();
      return;
    }
    setState(() => _coaching = true);
    final all = await TodoService.getAll();
    final habits = await HabitService.getAll();
    final sessions = await PomodoroService.getSessions();
    final behaviorContext = BehaviorInsightsService.summarize(
      tasks: all,
      habits: habits,
      sessions: sessions,
    );
    final result = await GroqService.focusCoach(
      _openTasks,
      behaviorContext: behaviorContext,
    );
    if (!mounted) return;
    setState(() => _coaching = false);
    if (!result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.error ?? 'Could not get a suggestion',
            style: T.footnote(c: Colors.white)),
        backgroundColor: AppColors.textPrimary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      ));
      return;
    }
    final FocusSuggestion s = result.data!;
    // Auto-bind if the model echoed a real task title.
    if (s.hasTask &&
        _openTasks.any((t) => t.title == s.taskTitle) &&
        !_running) {
      setState(() => _boundTaskTitle = s.taskTitle);
    }
    if (mounted) _showCoachNote(s);
  }

  void _showCoachNote(FocusSuggestion s) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: StickyNote(
          color: AppColors.hlLavender,
          tilt: -0.01,
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.auto_awesome_rounded,
                    size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Text('Focus coach', style: T.title3().copyWith(fontSize: 22)),
              ]),
              const SizedBox(height: 8),
              if (s.hasTask)
                Text(s.taskTitle,
                    style: T.body().copyWith(fontWeight: FontWeight.w800)),
              if (s.hasTask) const SizedBox(height: 4),
              Text(s.message,
                  style: T.body(c: AppColors.textPrimary).copyWith(height: 1.35)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    final progress =
        _totalSeconds == 0 ? 0.0 : 1 - (_remaining.inSeconds / _totalSeconds);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Focus', style: T.largeTitle()),
              const SizedBox(height: 2),
              Text('One thing at a time.',
                  style: T.body(c: AppColors.textSecondary)),
              const SizedBox(height: 20),
              _roundDots(),
              const SizedBox(height: 18),
              Center(child: _timerRing(progress)),
              const SizedBox(height: 22),
              _boundTaskCard(),
              const SizedBox(height: 18),
              _controls(),
              const SizedBox(height: 22),
              _sessionsCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundDots() {
    final total = _config.roundsBeforeLongBreak;
    final filled = _completedWorkRounds % total;
    final display = (_phase == PomodoroPhase.longBreak) ? total : filled;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i < display ? 12 : 9,
            height: i < display ? 12 : 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < display ? _phaseColor : AppColors.border,
            ),
          ),
      ],
    );
  }

  Widget _timerRing(double progress) {
    final m = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return SizedBox(
      width: 264,
      height: 264,
      child: CustomPaint(
        painter: _RingPainter(progress: progress, color: _phaseColor),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HighlighterLabel(
                _phase.label,
                color: _phase == PomodoroPhase.work
                    ? AppColors.hlPeach
                    : AppColors.hlMint,
              ),
              const SizedBox(height: 12),
              Text('$m:$s',
                  style: T.num(66, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(_running ? 'in progress' : 'paused',
                  style: T.footnote(c: AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boundTaskCard() {
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      onTap: _pickTask,
      child: Row(children: [
        Icon(
          _boundTaskTitle == null
              ? Icons.radio_button_unchecked_rounded
              : Icons.adjust_rounded,
          size: 20,
          color: _boundTaskTitle == null ? AppColors.textMuted : AppColors.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_boundTaskTitle == null ? 'No task selected' : 'Focusing on',
                  style: T.footnote(c: AppColors.textMuted)),
              if (_boundTaskTitle != null)
                Text(_boundTaskTitle!,
                    style: T.body().copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        // AI focus-coach button.
        GestureDetector(
          onTap: _askCoach,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.accentLight,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_coaching)
                const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accent))
              else
                const Icon(Icons.auto_awesome_rounded,
                    size: 15, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(_aiConfigured ? 'Coach' : 'Pick',
                  style: T.footnote(c: AppColors.accent)
                      .copyWith(fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _controls() {
    return Row(children: [
      _circleButton(Icons.refresh_rounded, _reset, tooltip: 'Reset'),
      const SizedBox(width: 14),
      Expanded(
        child: SizedBox(
          height: 58,
          child: FilledButton(
            onPressed: _running ? _pause : _start,
            style: FilledButton.styleFrom(
              backgroundColor: _phaseColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.xl)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white, size: 26),
                const SizedBox(width: 6),
                Text(_running ? 'Pause' : 'Start',
                    style: T.headline(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(width: 14),
      _circleButton(Icons.skip_next_rounded, _skip, tooltip: 'Skip phase'),
    ]);
  }

  Widget _circleButton(IconData icon, VoidCallback onTap, {String? tooltip}) {
    final btn = SizedBox(
      width: 52,
      height: 52,
      child: Material(
        color: AppColors.card,
        shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(icon, color: AppColors.textSecondary, size: 24),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
  }

  Widget _sessionsCard() {
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const HighlighterLabel('Today', color: AppColors.hlYellow),
              const SizedBox(height: 10),
              Text(
                _sessionsToday == 0
                    ? 'No focus sessions yet'
                    : '$_sessionsToday session${_sessionsToday == 1 ? '' : 's'} · $_minutesToday min',
                style: T.title3().copyWith(fontSize: 20),
              ),
            ],
          ),
        ),
        const Text('🍅', style: TextStyle(fontSize: 34)),
      ]),
    ).animate().fadeIn(duration: 300.ms);
  }
}

/// Paints the timer's progress ring: a faint full track plus a coloured arc
/// sweeping clockwise from 12 o'clock.
class _RingPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;
  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - 16) / 2;
    const stroke = 14.0;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppColors.fill;
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// Bottom sheet to bind (or clear) the focus task — lists today's open tasks.
class _TaskPickerSheet extends StatelessWidget {
  final List<TodoTask> tasks;
  final String? current;
  const _TaskPickerSheet({required this.tasks, required this.current});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.x2)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Text('Focus on', style: T.title3()),
              const SizedBox(height: 10),
              if (tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('No open tasks for today — add one first.',
                      style: T.footnote()),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.45),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final t in tasks)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            t.title == current
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: t.title == current
                                ? AppColors.primary
                                : AppColors.textMuted,
                          ),
                          title: Text(t.title, style: T.body()),
                          onTap: () => Navigator.pop(context, t.title),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              if (current != null)
                TextButton(
                  onPressed: () => Navigator.pop(context, ''),
                  child: Text('Clear selection',
                      style: T.footnote(c: AppColors.danger)
                          .copyWith(fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
