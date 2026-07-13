import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/alarm_tone_service.dart';
import '../widgets/ink_widgets.dart';

/// Alarm/notification tone picker — lists Android's own notification-type
/// system sounds (gentler than the jarring default alarm sound; see
/// AlarmToneHelper.kt), with tap-to-preview-and-select, mirroring
/// FontPickerScreen's instant-apply pattern.
class AlarmTonePickerScreen extends StatefulWidget {
  const AlarmTonePickerScreen({super.key});
  @override
  State<AlarmTonePickerScreen> createState() => _AlarmTonePickerScreenState();
}

class _AlarmTonePickerScreenState extends State<AlarmTonePickerScreen> {
  bool _loading = true;
  List<AlarmTone> _tones = const [];
  String? _selectedUri;
  String? _previewingUri;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    AlarmToneService.stopPreview();
    super.dispose();
  }

  Future<void> _load() async {
    final tones = await AlarmToneService.listAvailableTones();
    final selected = await AlarmToneService.getSelectedUri();
    if (!mounted) return;
    setState(() {
      _tones = tones;
      _selectedUri = selected;
      _loading = false;
    });
  }

  Future<void> _select(AlarmTone tone) async {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedUri = tone.uri;
      _previewingUri = tone.uri;
    });
    await AlarmToneService.setSelectedTone(tone);
    await AlarmToneService.previewTone(tone.uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text('Alarm & Notification Tone', style: T.title2()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                Text(
                  'Tap a tone to preview and set it — used for both task '
                  'alarms and reminder notifications.',
                  style: T.body(c: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                const HighlighterLabel('System tones', color: AppColors.hlMint),
                const SizedBox(height: 12),
                if (_tones.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No system tones found on this device.',
                      style: T.body(c: AppColors.textMuted),
                    ),
                  )
                else
                  for (final tone in _tones) _toneCard(tone),
              ],
            ),
    );
  }

  Widget _toneCard(AlarmTone tone) {
    final active = _selectedUri == tone.uri;
    final previewing = _previewingUri == tone.uri;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PaperCard(
        onTap: () => _select(tone),
        color: active ? AppColors.primaryLight : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(
            previewing ? Icons.volume_up_rounded : Icons.music_note_rounded,
            color: active ? AppColors.primary : AppColors.textMuted,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(tone.title,
                style: T.body().copyWith(fontWeight: FontWeight.w600)),
          ),
          if (active)
            const Icon(Icons.check_circle_rounded,
                color: AppColors.primary, size: 22)
          else
            const Icon(Icons.circle_outlined,
                color: AppColors.textHint, size: 22),
        ]),
      ),
    );
  }
}
