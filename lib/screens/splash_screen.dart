import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Premium animated splash. Renders for ~1.6s then calls `onDone`.
class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SplashScreen({super.key, required this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _titleFade;
  late final Animation<double> _taglineFade;
  late final Animation<double> _bgFade;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.primaryDark,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _bgFade = CurvedAnimation(parent: _ctrl,
        curve: const Interval(0, 0.3, curve: Curves.easeOut));
    _logoScale = Tween(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl,
          curve: const Interval(0.05, 0.55, curve: Curves.easeOutBack)),
    );
    _logoFade = CurvedAnimation(parent: _ctrl,
        curve: const Interval(0.05, 0.45, curve: Curves.easeOut));
    _titleFade = CurvedAnimation(parent: _ctrl,
        curve: const Interval(0.35, 0.7, curve: Curves.easeOut));
    _taglineFade = CurvedAnimation(parent: _ctrl,
        curve: const Interval(0.55, 0.9, curve: Curves.easeOut));

    _ctrl.forward();
    Timer(const Duration(milliseconds: 1700), () {
      if (mounted) {
        SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: AppColors.bg,
          systemNavigationBarIconBrightness: Brightness.dark,
        ));
        widget.onDone();
      }
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Stack(
          fit: StackFit.expand,
          children: [
            // Background gradient
            Opacity(
              opacity: _bgFade.value,
              child: const DecoratedBox(
                decoration: BoxDecoration(gradient: AppColors.heroGradient),
              ),
            ),

            // Soft animated radial glows
            _Glow(
              alignment: Alignment.topRight,
              color: Colors.white.withValues(alpha: 0.20 * _bgFade.value),
              size: 320,
            ),
            _Glow(
              alignment: Alignment.bottomLeft,
              color: AppColors.accentLight.withValues(alpha: 0.30 * _bgFade.value),
              size: 260,
            ),

            // Content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Opacity(
                    opacity: _logoFade.value,
                    child: Transform.scale(
                      scale: _logoScale.value,
                      child: const _LogoMark(),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Opacity(
                    opacity: _titleFade.value,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - _titleFade.value)),
                      child: const Text(
                        'InkList',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Opacity(
                    opacity: _taglineFade.value,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(Radii.pill),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: const Text(
                        'Plan it. InkList remembers.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom credit
            Positioned(
              bottom: 36,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: _taglineFade.value,
                child: Column(
                  children: [
                    Container(
                      width: 32,
                      height: 2,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Developed by Rohit Singh',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The InkList mark: a bold ink checkmark on the brand gradient, matching
/// the app's adaptive launcher icon (see android ic_launcher_foreground.xml)
/// so the splash and the icon read as the same brand.
class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104, height: 104,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: AppColors.heroGradient,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 32, offset: const Offset(0, 14),
          ),
        ],
      ),
      child: CustomPaint(
        size: const Size(104, 104),
        painter: _CheckmarkPainter(),
      ),
    );
  }
}

/// Draws the same checkmark geometry as the native icon's foreground vector
/// (a 108x108 safe zone, points (32,58)-(47,72)-(80,34)), scaled to fit.
class _CheckmarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 108;
    final path = Path()
      ..moveTo(32 * s, 58 * s)
      ..lineTo(47 * s, 72 * s)
      ..lineTo(80 * s, 34 * s);

    canvas.save();
    canvas.translate(0.4 * s, 2.2 * s);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..strokeWidth = 14 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 14 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Glow extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final double size;
  const _Glow({required this.alignment, required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
