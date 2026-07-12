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
      systemNavigationBarColor: Color(0xFF312E81),
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
      backgroundColor: const Color(0xFF312E81),
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

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96, height: 96,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFE0E7FF)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 30, offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Currency symbol with stylized chart bars
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('₹',
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryDark,
                  height: 1,
                )),
          ),
          // Tiny chart bars at the bottom
          Positioned(
            bottom: 14,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                _Bar(height: 6, color: AppColors.primary),
                SizedBox(width: 3),
                _Bar(height: 10, color: AppColors.primary),
                SizedBox(width: 3),
                _Bar(height: 8,  color: AppColors.accent),
                SizedBox(width: 3),
                _Bar(height: 14, color: AppColors.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double height;
  final Color color;
  const _Bar({required this.height, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 3, height: height,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1.5)),
  );
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
