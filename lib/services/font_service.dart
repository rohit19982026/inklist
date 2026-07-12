import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_fonts.dart';

/// Persists the user's chosen app font and hydrates [AppFonts] at startup.
class FontService {
  static const _key = 'app_font_id';

  /// Load the saved font into memory before the first frame so there's no
  /// font "flash". Call in main() before runApp.
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getString(_key);
    if (id != null) AppFonts.revision.value = AppFonts.byId(id).id;
  }

  static Future<String> getFontId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_key) ?? AppFonts.defaultId;
  }

  /// Apply [id] live (via [AppFonts]) and persist it.
  static Future<void> setFont(String id) async {
    AppFonts.select(id);
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, AppFonts.byId(id).id);
  }
}
