import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return IconButton(
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) {
          return RotationTransition(
            turns: animation,
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: Icon(
          isDark ? Icons.light_mode : Icons.dark_mode,
          key: ValueKey<bool>(isDark),
          color: isDark ? Colors.amber : null,
        ),
      ),
      tooltip: isDark ? l10n.themeLight : l10n.themeDark,
      onPressed: () {
        appThemeModeNotifier.value =
            isDark ? ThemeMode.light : ThemeMode.dark;
      },
    );
  }
}
