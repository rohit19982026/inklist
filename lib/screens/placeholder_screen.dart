import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Temporary placeholder for tabs whose real UI ships in later phases.
class PlaceholderScreen extends StatelessWidget {
  final String title;
  final String message;
  const PlaceholderScreen({super.key, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: T.body(c: AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}
