import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../controllers/device_controller.dart';
import '../models/throughput_unit.dart';

class WriteTestPanel extends StatelessWidget {
  final DeviceController controller;
  final ThroughputUnit unit;
  final int intervalMs;

  const WriteTestPanel({super.key, required this.controller, required this.unit, required this.intervalMs});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text("Характеристика для записи:", style: TextStyle(fontWeight: FontWeight.bold)),
        if (controller.writableCharacteristics.isEmpty)
          const Text("Нет доступных характеристик")
        else
          DropdownButton<BluetoothCharacteristic>(
            isExpanded: true,
            value: controller.selectedCharacteristic,
            items: controller.writableCharacteristics.map((c) => DropdownMenuItem(value: c, child: Text("${c.uuid}\n(Write)", style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (v) {
              controller.selectedCharacteristic = v;
              controller.notifyListeners();
            },
          ),
        const SizedBox(height: 20),
        ValueListenableBuilder<bool>(
          valueListenable: controller.isTestingNotifier,
          builder: (context, isTesting, child) => ElevatedButton(
            onPressed: isTesting ? null : () => controller.runWriteTest(unit, intervalMs),
            child: isTesting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("Запустить Write тест"),
          )
        ),
      ],
    );
  }
}

class NotifyTestPanel extends StatelessWidget {
  final DeviceController controller;
  final ThroughputUnit unit;
  final int intervalMs;

  const NotifyTestPanel({super.key, required this.controller, required this.unit, required this.intervalMs});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text("Характеристика для чтения (Notify):", style: TextStyle(fontWeight: FontWeight.bold)),
        if (controller.notifyCharacteristics.isEmpty)
          const Text("Нет доступных характеристик")
        else
          ValueListenableBuilder<bool>(
            valueListenable: controller.isTestingNotifier,
            builder: (context, isTesting, child) => DropdownButton<BluetoothCharacteristic>(
              isExpanded: true,
              value: controller.selectedNotifyCharacteristic,
              items: controller.notifyCharacteristics.map((c) {
                bool isTarget = c.serviceUuid.toString() == "7ec70001-0f5b-4777-ad1d-5add0ac66680";
                return DropdownMenuItem(value: c, child: Text("${c.uuid}\n${isTarget ? '(Target Service)' : ''}", style: TextStyle(fontSize: 12, color: isTarget ? Colors.blue : null)));
              }).toList(),
              onChanged: isTesting ? null : (v) {
                controller.selectedNotifyCharacteristic = v;
                controller.notifyListeners();
              },
            )
          ),
        const SizedBox(height: 20),
        ValueListenableBuilder<bool>(
          valueListenable: controller.isTestingNotifier,
          builder: (context, isTesting, child) => ElevatedButton(
            onPressed: () => controller.toggleNotificationTest(unit, intervalMs),
            style: ElevatedButton.styleFrom(backgroundColor: isTesting ? Colors.red : Theme.of(context).primaryColor, foregroundColor: Colors.white),
            child: Text(isTesting ? "Остановить тест" : "Старт Notify тест"),
          )
        ),
      ],
    );
  }
}