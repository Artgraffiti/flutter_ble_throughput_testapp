import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';

class ThemeModeMenuButton extends StatelessWidget {
  const ThemeModeMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ThemeControllerScope.of(context);
    final currentMode = controller.mode;

    return PopupMenuButton<ThemeMode>(
      tooltip: 'Тема',
      icon: Icon(_iconFor(currentMode)),
      initialValue: currentMode,
      onSelected: controller.setMode,
      itemBuilder: (context) => [
        _buildItem(
          mode: ThemeMode.system,
          currentMode: currentMode,
          icon: Icons.brightness_auto,
          label: 'Системная',
        ),
        _buildItem(
          mode: ThemeMode.light,
          currentMode: currentMode,
          icon: Icons.light_mode,
          label: 'Светлая',
        ),
        _buildItem(
          mode: ThemeMode.dark,
          currentMode: currentMode,
          icon: Icons.dark_mode,
          label: 'Темная',
        ),
      ],
    );
  }

  PopupMenuEntry<ThemeMode> _buildItem({
    required ThemeMode mode,
    required ThemeMode currentMode,
    required IconData icon,
    required String label,
  }) {
    return CheckedPopupMenuItem<ThemeMode>(
      value: mode,
      checked: mode == currentMode,
      child: Row(
        children: [Icon(icon), const SizedBox(width: 12), Text(label)],
      ),
    );
  }

  IconData _iconFor(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
      case ThemeMode.system:
        return Icons.brightness_auto;
    }
  }
}
