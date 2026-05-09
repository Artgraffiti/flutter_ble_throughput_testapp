import 'package:ble_throughput/theme/theme_controller.dart';
import 'package:ble_throughput/widgets/theme_mode_menu_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ThemeController uses system theme by default', () {
    final controller = ThemeController();

    expect(controller.mode, ThemeMode.system);

    controller.dispose();
  });

  testWidgets('Theme menu changes theme mode', (tester) async {
    final controller = ThemeController();

    await tester.pumpWidget(
      ThemeControllerScope(
        controller: controller,
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: controller,
          builder: (context, themeMode, child) {
            return MaterialApp(
              themeMode: themeMode,
              theme: ThemeData(useMaterial3: true),
              darkTheme: ThemeData.dark(useMaterial3: true),
              home: Scaffold(
                appBar: AppBar(actions: const [ThemeModeMenuButton()]),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byTooltip('Тема'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<ThemeMode> &&
            widget.value == ThemeMode.dark,
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.mode, ThemeMode.dark);

    controller.dispose();
  });
}
