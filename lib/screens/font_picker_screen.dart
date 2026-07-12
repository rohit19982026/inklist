import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../theme/app_fonts.dart';
import '../services/font_service.dart';
import '../widgets/ink_widgets.dart';

/// Font picker — 21 fonts split into natural-handwriting and clean/normal
/// groups, each shown with a live preview. Tapping applies instantly and
/// app-wide (the whole tree re-themes via [AppFonts.revision]).
class FontPickerScreen extends StatefulWidget {
  const FontPickerScreen({super.key});
  @override
  State<FontPickerScreen> createState() => _FontPickerScreenState();
}

class _FontPickerScreenState extends State<FontPickerScreen> {
  static const _sample = 'The quick brown fox\njumps over 12 lazy dogs';

  Future<void> _select(String id) async {
    HapticFeedback.selectionClick();
    await FontService.setFont(id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final selected = AppFonts.family;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text('Font', style: T.title2()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            'Pick the writing that feels most like you. It applies everywhere, '
            'instantly.',
            style: T.body(c: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          const HighlighterLabel('Handwritten', color: AppColors.hlPink),
          const SizedBox(height: 12),
          for (final f in AppFonts.handwritten)
            _fontCard(f, selected == f.id),
          const SizedBox(height: 22),
          const HighlighterLabel('Clean & normal', color: AppColors.hlSky),
          const SizedBox(height: 12),
          for (final f in AppFonts.clean) _fontCard(f, selected == f.id),
        ],
      ),
    );
  }

  Widget _fontCard(AppFontOption f, bool active) {
    final previewStyle = GoogleFonts.getFont(
      f.id,
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
      height: 1.15,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PaperCard(
        onTap: () => _select(f.id),
        color: active ? AppColors.primaryLight : null,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(f.label,
                    style: T.body().copyWith(fontWeight: FontWeight.w700)),
              ),
              if (active)
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.primary, size: 22)
              else
                const Icon(Icons.circle_outlined,
                    color: AppColors.textHint, size: 22),
            ]),
            const SizedBox(height: 8),
            Text(_sample, style: previewStyle),
          ],
        ),
      ),
    );
  }
}
