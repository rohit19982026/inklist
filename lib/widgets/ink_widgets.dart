import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared "paper planner" building blocks for InkList's handwritten UI.
///
/// These give every screen the same warm, hand-made feel: soft paper cards,
/// pastel highlighter labels, tilted sticky notes, and an animated ink
/// checkbox. Screens compose these rather than re-styling raw Containers.

/// A soft, off-white "sheet of paper" card with a hairline border and gentle
/// shadow. Optionally tilts a hair for a hand-placed look.
class PaperCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? color;
  final double tilt; // radians; keep tiny (~0.01) for a natural look
  final VoidCallback? onTap;
  const PaperCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = Radii.xl,
    this.color,
    this.tilt = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = Container(
      decoration: BoxDecoration(
        color: color ?? AppColors.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.softShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (tilt != 0) card = Transform.rotate(angle: tilt, child: card);
    return card;
  }
}

/// A pastel "highlighter" pill behind a short label — the marker-swipe look
/// used for section titles in the reference planners.
class HighlighterLabel extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const HighlighterLabel(this.text,
      {super.key, this.color = AppColors.hlYellow, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: AppColors.textPrimary),
          const SizedBox(width: 6),
        ],
        Text(text,
            style: T.title3().copyWith(fontSize: 20, height: 1.0)),
      ]),
    );
  }
}

/// A small tilted sticky note in a pastel colour — for callouts / tips.
class StickyNote extends StatelessWidget {
  final Widget child;
  final Color color;
  final double tilt;
  final EdgeInsets padding;
  const StickyNote({
    super.key,
    required this.child,
    this.color = AppColors.hlMint,
    this.tilt = -0.02,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: tilt,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(Radii.md),
          boxShadow: AppColors.softShadow,
        ),
        child: child,
      ),
    );
  }
}

/// A hand-drawn-style checkbox that fills with coral ink and pops a check when
/// toggled on. Tap toggles [onChanged].
class InkCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double size;
  final Color activeColor;
  const InkCheckbox({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 26,
    this.activeColor = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: value ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value ? activeColor : AppColors.textHint,
            width: 2.4,
          ),
        ),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          scale: value ? 1 : 0,
          child: Icon(Icons.check_rounded,
              size: size * 0.7, color: Colors.white),
        ),
      ),
    );
  }
}
