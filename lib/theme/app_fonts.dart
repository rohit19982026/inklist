import 'package:flutter/foundation.dart';

/// A selectable app font. [id] doubles as the exact Google Fonts family name
/// passed to `GoogleFonts.getFont`, so it must match Google Fonts verbatim.
class AppFontOption {
  final String id;
  final String label;
  final bool handwritten; // true = natural handwriting, false = clean/normal
  const AppFontOption(this.id, this.label, {this.handwritten = true});
}

/// The app's font registry + the live current selection.
///
/// [family] is read synchronously by the `T` typography helpers on every
/// build, and [revision] is a [ValueListenable] the app root listens to so a
/// font change re-themes the whole tree instantly. [FontService] owns the
/// persistence; this class owns the in-memory truth.
class AppFonts {
  AppFonts._();

  /// 11 natural, human-handwriting fonts (print + relaxed cursive that still
  /// reads clearly at body sizes — deliberately not loopy formal script).
  static const List<AppFontOption> handwritten = [
    AppFontOption('Patrick Hand', 'Patrick Hand'),
    AppFontOption('Kalam', 'Kalam'),
    AppFontOption('Shadows Into Light', 'Shadows Into Light'),
    AppFontOption('Indie Flower', 'Indie Flower'),
    AppFontOption('Architects Daughter', 'Architects Daughter'),
    AppFontOption('Gochi Hand', 'Gochi Hand'),
    AppFontOption('Handlee', 'Handlee'),
    AppFontOption('Coming Soon', 'Coming Soon'),
    AppFontOption('Neucha', 'Neucha'),
    AppFontOption('Gaegu', 'Gaegu'),
    AppFontOption('Caveat', 'Caveat'),
  ];

  /// 10 clean, non-cursive fonts for people who prefer a plain look.
  static const List<AppFontOption> clean = [
    AppFontOption('Inter', 'Inter', handwritten: false),
    AppFontOption('Nunito', 'Nunito', handwritten: false),
    AppFontOption('Poppins', 'Poppins', handwritten: false),
    AppFontOption('Rubik', 'Rubik', handwritten: false),
    AppFontOption('Work Sans', 'Work Sans', handwritten: false),
    AppFontOption('Quicksand', 'Quicksand', handwritten: false),
    AppFontOption('Mulish', 'Mulish', handwritten: false),
    AppFontOption('Lato', 'Lato', handwritten: false),
    AppFontOption('Karla', 'Karla', handwritten: false),
    AppFontOption('DM Sans', 'DM Sans', handwritten: false),
  ];

  static List<AppFontOption> get all => [...handwritten, ...clean];

  /// A natural print-handwriting default — replaces the old marker/cursive
  /// Caveat default, which read as unnatural.
  static const String defaultId = 'Patrick Hand';

  /// Numerals (timer, counters) stay on one stable, tabular-friendly sans so
  /// they never jitter or become hard to read, whatever font is selected.
  static const String numeralFamily = 'Nunito';

  /// Live selection. The app root rebuilds its theme when this changes.
  static final ValueNotifier<String> revision = ValueNotifier<String>(defaultId);

  static String get family => revision.value;

  static AppFontOption current() => byId(family);

  static AppFontOption byId(String? id) => all.firstWhere(
        (f) => f.id == id,
        orElse: () => all.firstWhere((f) => f.id == defaultId),
      );

  /// Update the in-memory selection (persistence is handled by FontService).
  static void select(String id) {
    revision.value = byId(id).id;
  }
}
