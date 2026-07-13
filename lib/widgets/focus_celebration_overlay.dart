import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';

/// A celebratory burst shown when a Pomodoro work session completes — a
/// "PUBG chicken dinner"-style payoff for finishing a full focus session.
/// The animation itself is plain hand-rolled Flutter (no confetti/particle
/// package) so it never depends on a third-party lib; only the message text
/// is AI-generated, and even that starts from an instant local fallback so
/// the celebration never waits on a network call to appear.
class FocusCelebrationOverlay extends StatefulWidget {
  final String message;
  final Future<String?>? betterMessage;

  const FocusCelebrationOverlay({
    super.key,
    required this.message,
    this.betterMessage,
  });

  static const List<String> localMessages = [
    'Nice focus! 🔥',
    'That\'s a full session.',
    'Deep work, done.',
    'One more in the books.',
    'Momentum builder.',
    'Locked in — nailed it.',
  ];

  static String randomLocalMessage() =>
      localMessages[math.Random().nextInt(localMessages.length)];

  /// Shows the overlay immediately with [message]; if [betterMessage]
  /// resolves (an AI-generated line) while the overlay is still on screen,
  /// the text hot-swaps in with a brief fade. Auto-dismisses on its own —
  /// callers don't need to await this beyond fire-and-forget.
  static Future<void> show(
    BuildContext context, {
    required String message,
    Future<String?>? betterMessage,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => FocusCelebrationOverlay(
        message: message,
        betterMessage: betterMessage,
      ),
      transitionBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    );
  }

  @override
  State<FocusCelebrationOverlay> createState() =>
      _FocusCelebrationOverlayState();
}

class _FocusCelebrationOverlayState extends State<FocusCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burst;
  late final List<_Particle> _particles;
  late String _message;
  bool _dismissed = false;

  static const _autoDismissAfter = Duration(milliseconds: 2800);

  @override
  void initState() {
    super.initState();
    _message = widget.message;
    _particles = _generateParticles();
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    widget.betterMessage?.then((text) {
      if (!mounted || _dismissed || text == null || text.trim().isEmpty) return;
      setState(() => _message = text.trim());
    });

    Future.delayed(_autoDismissAfter, _dismiss);
  }

  void _dismiss() {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  List<_Particle> _generateParticles() {
    final rnd = math.Random();
    const count = 16;
    return List.generate(count, (i) {
      final baseAngle = (2 * math.pi / count) * i;
      final angle = baseAngle + (rnd.nextDouble() - 0.5) * 0.4;
      final distance = 70.0 + rnd.nextDouble() * 90.0;
      final size = 6.0 + rnd.nextDouble() * 8.0;
      final color = AppColors.highlighters[i % AppColors.highlighters.length];
      return _Particle(angle: angle, distance: distance, size: size, color: color);
    });
  }

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dismiss,
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: SizedBox(
            width: 280,
            height: 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _burst,
                  builder: (context, _) => CustomPaint(
                    size: const Size(280, 280),
                    painter: _ParticlePainter(_particles, _burst.value),
                  ),
                ),
                _badge(),
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 180.ms);
  }

  Widget _badge() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: AppColors.card,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.local_fire_department_rounded,
              color: AppColors.primary, size: 44),
        )
            .animate()
            .scale(
              begin: const Offset(0.4, 0.4),
              end: const Offset(1, 1),
              duration: 420.ms,
              curve: Curves.elasticOut,
            ),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Padding(
            key: ValueKey(_message),
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              _message,
              textAlign: TextAlign.center,
              style: T.headline(color: Colors.white),
            ),
          ),
        ).animate().fadeIn(delay: 200.ms, duration: 300.ms),
      ],
    );
  }
}

class _Particle {
  final double angle;
  final double distance;
  final double size;
  final Color color;
  const _Particle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.color,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double t; // 0..1 animation progress

  _ParticlePainter(this.particles, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Ease-out travel, fade in fast then out over the back half.
    final travel = Curves.easeOutCubic.transform(t);
    final opacity = t < 0.55 ? 1.0 : (1.0 - (t - 0.55) / 0.45).clamp(0.0, 1.0);
    for (final p in particles) {
      final offset = Offset(math.cos(p.angle), math.sin(p.angle)) * p.distance * travel;
      final paint = Paint()..color = p.color.withValues(alpha: opacity);
      canvas.drawCircle(center + offset, p.size * (0.6 + 0.4 * travel), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => oldDelegate.t != t;
}
