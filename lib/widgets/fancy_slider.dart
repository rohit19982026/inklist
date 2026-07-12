import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class FancySlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final List<Color> colors;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String? minLabel;
  final String? maxLabel;
  final String Function(double)? labelBuilder;

  const FancySlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.colors,
    required this.onChanged,
    this.onChangeEnd,
    this.divisions,
    this.minLabel,
    this.maxLabel,
    this.labelBuilder,
  });

  @override
  State<FancySlider> createState() => _FancySliderState();
}

class _FancySliderState extends State<FancySlider>
    with SingleTickerProviderStateMixin {
  late final AnimationController _labelCtrl;

  @override
  void initState() {
    super.initState();
    _labelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.colors.last;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SliderTheme(
        data: SliderThemeData(
          trackHeight: 8,
          trackShape: _GradientTrackShape(
            gradient: LinearGradient(colors: widget.colors),
            inactiveColor: AppColors.fill,
          ),
          thumbShape: _HaloThumbShape(ring: accent),
          overlayShape: SliderComponentShape.noOverlay,
          activeTickMarkColor: Colors.transparent,
          inactiveTickMarkColor: Colors.transparent,
          showValueIndicator: ShowValueIndicator.never,
        ),
        child: Slider(
          value: widget.value.clamp(widget.min, widget.max),
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          onChanged: widget.onChanged,
          onChangeStart: (_) => _labelCtrl.forward(),
          onChangeEnd: (v) {
            _labelCtrl.reverse();
            widget.onChangeEnd?.call(v);
          },
        ),
      ),
      if (widget.minLabel != null || widget.maxLabel != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
          child: Row(children: [
            if (widget.minLabel != null) Text(widget.minLabel!, style: T.caption2()),
            const Spacer(),
            if (widget.maxLabel != null) Text(widget.maxLabel!, style: T.caption2()),
          ]),
        ),
    ]);
  }
}

class _GradientTrackShape extends RoundedRectSliderTrackShape {
  final LinearGradient gradient;
  final Color inactiveColor;
  const _GradientTrackShape({required this.gradient, required this.inactiveColor});

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final radius = Radius.circular(rect.height / 2);
    final canvas = context.canvas;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = inactiveColor,
    );

    final active = Rect.fromLTRB(rect.left, rect.top, thumbCenter.dx, rect.bottom);
    if (active.width > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(active, radius),
        Paint()..shader = gradient.createShader(rect),
      );
    }
  }
}

class _HaloThumbShape extends SliderComponentShape {
  final Color ring;
  const _HaloThumbShape({required this.ring});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(28, 28);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final r = 11.0 + activationAnimation.value * 2.5;

    // Outer glow while pressing
    if (activationAnimation.value > 0) {
      canvas.drawCircle(
        center,
        r + 6 * activationAnimation.value,
        Paint()
          ..color = ring.withValues(alpha: 0.12 * activationAnimation.value),
      );
    }

    // Drop shadow
    canvas.drawCircle(
      center.translate(0, 1.5),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // White fill
    canvas.drawCircle(center, r, Paint()..color = Colors.white);
    // Accent ring
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..color = ring,
    );
    // Inner dot when pressing
    if (activationAnimation.value > 0.3) {
      canvas.drawCircle(
        center,
        3.0 * activationAnimation.value,
        Paint()..color = ring.withValues(alpha: 0.6),
      );
    }
  }
}
