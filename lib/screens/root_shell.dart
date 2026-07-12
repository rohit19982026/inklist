import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/smart_reminder_service.dart';
import 'todo_screen.dart';
import 'week_screen.dart';
import 'settings_screen.dart';
import 'placeholder_screen.dart';

/// InkList bottom-nav shell: Today / Week / Focus / Habits.
/// Settings + Premium live behind the app-bar gear on Today to keep the tab
/// bar to the 4 planner destinations.
class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    // Background housekeeping on every app launch.
    Future.microtask(() async {
      await SmartReminderService.syncSchedule();
    });
  }

  // Each tab kept alive via IndexedStack so state survives switching.
  late final List<Widget> _pages = const [
    TodoScreen(),
    WeekScreen(),
    PlaceholderScreen(title: 'Focus', message: 'Pomodoro focus timer — coming next.'),
    PlaceholderScreen(title: 'Habits', message: 'Habit tracker — coming next.'),
  ];

  static const _tabs = <(IconData, IconData, String)>[
    (Icons.wb_sunny_rounded,    Icons.wb_sunny_outlined,    'Today'),
    (Icons.view_week_rounded,   Icons.view_week_outlined,   'Week'),
    (Icons.timer_rounded,       Icons.timer_outlined,       'Focus'),
    (Icons.local_fire_department_rounded, Icons.local_fire_department_outlined, 'Habits'),
  ];

  void _select(int i) {
    if (i == _idx) return;
    HapticFeedback.selectionClick();
    setState(() => _idx = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(index: _idx, children: _pages),
      bottomNavigationBar: _NavBar(idx: _idx, onTap: _select, tabs: _tabs),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int idx;
  final void Function(int) onTap;
  final List<(IconData, IconData, String)> tabs;
  const _NavBar({required this.idx, required this.onTap, required this.tabs});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        boxShadow: [
          BoxShadow(color: Color(0x140F172A), blurRadius: 24, offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(tabs.length, (i) {
              final sel = idx == i;
              final t = tabs[i];
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primaryLight : Colors.transparent,
                      borderRadius: BorderRadius.circular(Radii.lg),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: (c, a) =>
                              ScaleTransition(scale: a, child: c),
                          child: Icon(
                            sel ? t.$1 : t.$2,
                            key: ValueKey(sel),
                            color: sel ? AppColors.primary : AppColors.textMuted,
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          t.$3,
                          style: T.caption2(
                            c: sel ? AppColors.primary : AppColors.textMuted,
                          ).copyWith(
                              fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                              fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Convenience for opening Settings from a screen app bar.
void openSettings(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const SettingsScreen()),
  );
}
