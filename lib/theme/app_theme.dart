import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Modern fintech design system — Plus Jakarta Sans + vibrant aesthetic palette.
///
/// Color direction: deep indigo brand anchor with vivid accents (coral, mint,
/// amber, cyan, violet) used purposefully across charts/KPIs. Heatmap uses a
/// warm cool→hot ramp. Trend charts use multi-stop gradients so the eye reads
/// progression rather than a flat line.
class AppColors {
  // ── Surfaces — warm paper ────────────────────────────────────────────────
  static const bg              = Color(0xFFFBF6EC);   // cream paper
  static const card            = Color(0xFFFFFDF8);   // white paper
  static const surface         = Color(0xFFF3ECDC);   // kraft
  static const elevated        = Color(0xFFFFFDF8);
  static const overlay         = Color(0xFFFCF8EF);

  // ── Brand — coral ink ────────────────────────────────────────────────────
  static const primary         = Color(0xFFEF6B52);   // coral (the "Save" accent)
  static const primaryDark     = Color(0xFFD4553D);
  static const primaryLight    = Color(0xFFFDE7E1);
  static const primaryGhost    = Color(0xFFFFF6F3);
  static const accent          = Color(0xFF7C6BD6);   // soft violet (AI)
  static const accentLight     = Color(0xFFEDE7FB);

  // ── Aesthetic accents (used across KPIs, charts, badges) ────────────────
  static const coral           = Color(0xFFFB7185);
  static const coralLight      = Color(0xFFFFE4E6);
  static const mint            = Color(0xFF10B981);
  static const mintLight       = Color(0xFFD1FAE5);
  static const amber           = Color(0xFFF59E0B);
  static const amberLight      = Color(0xFFFEF3C7);
  static const sky             = Color(0xFF0EA5E9);
  static const skyLight        = Color(0xFFE0F2FE);
  static const sunset          = Color(0xFFF97316);
  static const sunsetLight     = Color(0xFFFFEDD5);
  static const fuchsia         = Color(0xFFD946EF);
  static const fuchsiaLight    = Color(0xFFFAE8FF);

  // ── Semantic ─────────────────────────────────────────────────────────────
  static const success         = mint;
  static const successLight    = mintLight;
  static const danger          = Color(0xFFEF4444);
  static const dangerLight     = Color(0xFFFEE2E2);
  static const warning         = amber;
  static const warningLight    = amberLight;
  static const info            = sky;
  static const infoLight       = skyLight;

  // ── Legacy aliases ───────────────────────────────────────────────────────
  static const green   = success;
  static const red     = danger;
  static const blue    = info;
  static const teal    = Color(0xFF0891B2);
  static const indigo  = primary;
  static const purple  = accent;
  static const pink    = coral;

  // ── Text — ink ramp ─────────────────────────────────────────────────────
  static const textPrimary     = Color(0xFF2B2A28);   // charcoal ink
  static const textSecondary   = Color(0xFF6B6862);
  static const textMuted       = Color(0xFF9A968C);
  static const textHint        = Color(0xFFCFC8BA);

  // ── Highlighter pastels (planner blocks) ────────────────────────────────
  static const hlYellow        = Color(0xFFFFF3B0);
  static const hlPink          = Color(0xFFFFD9E3);
  static const hlMint          = Color(0xFFCDEFD8);
  static const hlLavender      = Color(0xFFE6DBFF);
  static const hlPeach         = Color(0xFFFFE2C7);
  static const hlSky           = Color(0xFFCDEAFB);
  static const List<Color> highlighters = [
    hlYellow, hlPink, hlMint, hlLavender, hlPeach, hlSky,
  ];

  // ── Lines / fills ────────────────────────────────────────────────────────
  static const border          = Color(0xFFE7DECC);
  static const divider         = Color(0xFFEFE7D6);
  static const fill            = Color(0xFFF4EEE1);
  static const fillSecondary   = Color(0xFFFAF6EC);

  // ── Chart palette (vivid, distinguishable) ──────────────────────────────
  static const chartPrimary    = primary;
  static const chartAccent     = accent;
  static const chartCoral      = coral;
  static const chartMint       = mint;
  static const chartAmber      = amber;
  static const chartSky        = sky;
  static const chartSunset     = sunset;
  static const chartFuchsia    = fuchsia;

  /// Ordered palette to cycle through for series colors / top-N lists.
  static const List<Color> chartCycle = [
    Color(0xFF4F46E5),   // indigo
    Color(0xFFF97316),   // sunset
    Color(0xFF10B981),   // mint
    Color(0xFFFB7185),   // coral
    Color(0xFF0EA5E9),   // sky
    Color(0xFFD946EF),   // fuchsia
    Color(0xFFF59E0B),   // amber
    Color(0xFF7C3AED),   // violet
  ];

  /// Trend-line gradient stops (cool → warm). Used for the main 30-day chart.
  static const List<Color> trendGradient = [
    Color(0xFF06B6D4),   // cyan
    Color(0xFF4F46E5),   // indigo
    Color(0xFFD946EF),   // fuchsia
  ];

  /// Sunset gradient — used for monthly totals chart.
  static const List<Color> sunsetGradient = [
    Color(0xFFF59E0B),   // amber
    Color(0xFFF97316),   // sunset
    Color(0xFFEF4444),   // red
  ];

  /// Ocean gradient — used for misc tertiary visualizations.
  static const List<Color> oceanGradient = [
    Color(0xFF10B981),   // mint
    Color(0xFF06B6D4),   // cyan
    Color(0xFF0EA5E9),   // sky
  ];

  // ── Heatmap (absolute-threshold: green → amber → red) ───────────────────
  // Vivid, easily distinguishable colors keyed to daily spend brackets.
  static const heatEmpty = Color(0xFFF1F5F9);
  static const heat1     = Color(0xFF34D399);   // emerald  — ₹1-500
  static const heat2     = Color(0xFFFBBF24);   // amber    — ₹500-1,500
  static const heat3     = Color(0xFFF97316);   // orange   — ₹1,500-3,000
  static const heat4     = Color(0xFFEF4444);   // red      — ₹3,000-5,000
  static const heat5     = Color(0xFFB91C1C);   // deep red — ₹5,000+

  // ── Category palette — vibrant, distinguishable ──────────────────────────
  static const Map<String, Color> categoryColors = {
    'Food Delivery'        : Color(0xFFEF4444),   // red
    'Groceries'            : Color(0xFF10B981),   // emerald
    'Dining Out'           : Color(0xFFF97316),   // orange
    'Online Shopping'      : Color(0xFFEC4899),   // pink
    'Transport'            : Color(0xFF3B82F6),   // blue
    'Fuel'                 : Color(0xFF78716C),   // stone
    'Entertainment'        : Color(0xFF8B5CF6),   // violet
    'Health & Pharmacy'    : Color(0xFF06B6D4),   // cyan
    'Electricity'          : Color(0xFFF59E0B),   // amber
    'Mobile & Internet'    : Color(0xFF6366F1),   // indigo
    'Travel'               : Color(0xFF14B8A6),   // teal
    'Investment'           : Color(0xFF16A34A),   // green
    'Savings'              : Color(0xFF0D9488),   // teal — money kept, not spent
    'Insurance'            : Color(0xFF64748B),   // slate
    'Rent & Housing'       : Color(0xFF0EA5E9),   // sky
    'Education'            : Color(0xFFA855F7),   // purple
    'Personal Care'        : Color(0xFFF43F5E),   // rose
    'Credit Card Payments' : Color(0xFFEAB308),   // gold/yellow
    'EMI & Loans'          : Color(0xFF7C3AED),   // violet
    'Additional'           : Color(0xFF4F46E5),   // brand indigo
    'Transfer'             : Color(0xFFD97706),
    'Household'            : Color(0xFF92400E),
    'Self Transfer'        : Color(0xFFCBD5E1),
    'Others'               : Color(0xFF94A3B8),
  };

  // ── Shadows ─────────────────────────────────────────────────────────────
  static const cardShadow = [
    BoxShadow(color: Color(0x0F0F172A), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x080F172A), blurRadius: 4,  offset: Offset(0, 1)),
  ];
  static const softShadow = [
    BoxShadow(color: Color(0x080F172A), blurRadius: 10, offset: Offset(0, 2)),
  ];
  static const tinyShadow = [
    BoxShadow(color: Color(0x05000000), blurRadius: 4, offset: Offset(0, 1)),
  ];
  static List<BoxShadow> coloredShadow(Color c) => [
    BoxShadow(color: c.withValues(alpha: 0.32), blurRadius: 28, offset: const Offset(0, 12)),
    BoxShadow(color: c.withValues(alpha: 0.12), blurRadius: 6,  offset: const Offset(0, 3)),
  ];

  // ── Gradients ────────────────────────────────────────────────────────────
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFFF6845F), Color(0xFFEF6B7D)],
  );
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFFF07E5C), Color(0xFFEF6B7D), Color(0xFF7C6BD6)],
  );
  static const sunsetCardGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFFF97316), Color(0xFFEF4444)],
  );
  static const oceanCardGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF06B6D4), Color(0xFF0EA5E9)],
  );
  static const mintCardGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF10B981), Color(0xFF059669)],
  );
  static const successGradient = mintCardGradient;
  static const dangerGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFFEF4444), Color(0xFFE11D48)],
  );
}

/// Spacing tokens
class Spacing {
  static const xs = 4.0; static const sm = 8.0; static const md = 12.0;
  static const lg = 16.0; static const xl = 20.0; static const x2 = 24.0;
  static const x3 = 32.0; static const x4 = 40.0;
}

/// Radius tokens
class Radii {
  static const sm = 8.0; static const md = 12.0; static const lg = 16.0;
  static const xl = 20.0; static const x2 = 24.0; static const pill = 999.0;
}

/// Typography — handwritten planner aesthetic.
/// Caveat (marker) for large titles, Kalam (legible handwriting) for body/UI.
class T {
  /// Legible handwriting — used for body, labels and most UI text.
  static TextStyle _f({
    required double size,
    required FontWeight weight,
    Color color = AppColors.textPrimary,
    double letterSpacing = 0,
    double? height,
    List<FontFeature>? features,
  }) =>
      GoogleFonts.kalam(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
        fontFeatures: features,
      );

  /// Marker-style handwriting — used for large headings only (stays legible big).
  static TextStyle _hand({
    required double size,
    required FontWeight weight,
    Color color = AppColors.textPrimary,
    double letterSpacing = 0,
    double? height,
  }) =>
      GoogleFonts.caveat(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  static TextStyle display(double size,
      {Color color = AppColors.textPrimary, double spacing = 0,
      FontWeight weight = FontWeight.w700}) =>
      _hand(size: size + 6, weight: weight, color: color, letterSpacing: spacing);

  static TextStyle hero({Color color = AppColors.textPrimary}) =>
      _hand(size: 48, weight: FontWeight.w700, color: color, letterSpacing: 0);

  static TextStyle largeTitle({Color color = AppColors.textPrimary}) =>
      _hand(size: 38, weight: FontWeight.w700, color: color, letterSpacing: 0);
  static TextStyle title1({Color color = AppColors.textPrimary}) =>
      _hand(size: 32, weight: FontWeight.w700, color: color, letterSpacing: 0);
  static TextStyle title2({Color color = AppColors.textPrimary}) =>
      _hand(size: 28, weight: FontWeight.w700, color: color, letterSpacing: 0);
  static TextStyle title3({Color color = AppColors.textPrimary}) =>
      _hand(size: 24, weight: FontWeight.w700, color: color, letterSpacing: 0);

  static TextStyle headline({Color color = AppColors.textPrimary}) =>
      _f(size: 16, weight: FontWeight.w700, color: color, letterSpacing: -0.2);
  static TextStyle body({Color c = AppColors.textPrimary}) =>
      _f(size: 15, weight: FontWeight.w500, color: c, letterSpacing: -0.1);
  static TextStyle callout({Color c = AppColors.textSecondary}) =>
      _f(size: 14, weight: FontWeight.w500, color: c);
  static TextStyle subhead({Color c = AppColors.textSecondary}) =>
      _f(size: 14, weight: FontWeight.w500, color: c);
  static TextStyle footnote({Color c = AppColors.textSecondary}) =>
      _f(size: 12, weight: FontWeight.w500, color: c);
  static TextStyle caption1({Color c = AppColors.textMuted}) =>
      _f(size: 11, weight: FontWeight.w600, color: c, letterSpacing: 0.2);
  static TextStyle caption2({Color c = AppColors.textMuted}) =>
      _f(size: 10, weight: FontWeight.w600, color: c, letterSpacing: 0.4);

  static TextStyle sectionHeader({Color c = AppColors.textMuted}) =>
      _f(size: 11, weight: FontWeight.w700, color: c, letterSpacing: 1.2);

  /// Tabular numerics — uses Plus Jakarta Sans with tabular figures (looks great
  /// for currency).
  static TextStyle num(double size, {Color color = AppColors.textPrimary,
      FontWeight weight = FontWeight.w800}) =>
      _f(size: size, weight: weight, color: color, letterSpacing: -0.3,
          features: [const FontFeature.tabularFigures()]);
}

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.card,
        onSurface: AppColors.textPrimary,
        error: AppColors.danger,
      ),
      textTheme: GoogleFonts.kalamTextTheme().apply(
        bodyColor: AppColors.textPrimary, displayColor: AppColors.textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent, elevation: 0,
        foregroundColor: AppColors.textPrimary,
        titleTextStyle: T.title3()),
      splashFactory: InkRipple.splashFactory,
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────

class IOSCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  const IOSCard({super.key, required this.child,
      this.padding = const EdgeInsets.all(16), this.radius = Radii.lg});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: AppColors.softShadow,
    ),
    child: ClipRRect(borderRadius: BorderRadius.circular(radius),
        child: Padding(padding: padding, child: child)),
  );
}

class IOSSection extends StatelessWidget {
  final String? header;
  final String? footer;
  final List<Widget> children;
  const IOSSection({super.key, this.header, this.footer, required this.children});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    if (header != null) Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Text(header!.toUpperCase(), style: T.sectionHeader())),
    Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.tinyShadow,
      ),
      child: Column(children: children.asMap().entries.map((e) => Column(children: [
        e.value,
        if (e.key < children.length - 1)
          const Divider(height: 1, indent: 56, endIndent: 0, color: AppColors.divider),
      ])).toList()),
    ),
    if (footer != null) Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Text(footer!, style: T.caption1())),
  ]);
}

class IOSTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;
  const IOSTile({super.key, required this.leading, required this.title,
      this.subtitle, this.trailing, this.onTap, this.titleColor});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          leading,
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: T.body(c: titleColor ?? AppColors.textPrimary)),
            if (subtitle != null) ...[const SizedBox(height: 2),
              Text(subtitle!, style: T.footnote())],
          ])),
          if (trailing != null) trailing!
          else if (onTap != null) const Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 20),
        ]),
      ),
    ),
  );
}
