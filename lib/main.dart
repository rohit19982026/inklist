import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'theme/app_fonts.dart';
import 'services/font_service.dart';
import 'screens/splash_screen.dart';
import 'screens/root_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Hydrate the saved font before the first frame so there's no font flash.
  await FontService.load();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: AppColors.bg,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const InkListApp());
}

class InkListApp extends StatefulWidget {
  const InkListApp({super.key});
  @override
  State<InkListApp> createState() => _InkListAppState();
}

class _InkListAppState extends State<InkListApp> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    // Rebuild the whole app (theme + all `T` text styles) when the font
    // selection changes, so the switch is instant and app-wide.
    return ValueListenableBuilder<String>(
      valueListenable: AppFonts.revision,
      builder: (context, _, __) => MaterialApp(
        title: 'InkList',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: _splashDone
              ? const RootShell()
              : SplashScreen(onDone: () => setState(() => _splashDone = true)),
        ),
      ),
    );
  }
}
