// ==> lib/widgets/test_panels.dart <==
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../controllers/device_controller.dart';
import '../models/imu_sensor_config.dart';
import '../models/throughput_unit.dart';

class WriteTestPanel extends StatelessWidget {
  final DeviceController controller;
  final ThroughputUnit unit;
  final int intervalMs;
  final Duration? duration;

  const WriteTestPanel({
    super.key,
    required this.controller,
    required this.unit,
    required this.intervalMs,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          "Характеристика для записи:",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        if (controller.writableCharacteristics.isEmpty)
          const Text("Нет доступных характеристик")
        else
          DropdownButton<BluetoothCharacteristic>(
            isExpanded: true,
            value: controller.selectedCharacteristic,
            items: controller.writableCharacteristics.map((c) {
              return DropdownMenuItem(
                value: c,
                child: Text(
                  "${c.uuid}\n(Write)",
                  style: const TextStyle(fontSize: 12),
                ),
              );
            }).toList(),
            onChanged: (v) {
              controller.selectWriteCharacteristic(v);
            },
          ),
        const SizedBox(height: 20),
        ValueListenableBuilder<bool>(
          valueListenable: controller.isTestingNotifier,
          builder: (context, isTesting, child) {
            return ElevatedButton(
              onPressed: isTesting
                  ? null
                  : () => controller.runWriteTest(
                      unit,
                      intervalMs,
                      duration: duration,
                    ),
              child: isTesting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("Запустить Write тест"),
            );
          },
        ),
      ],
    );
  }
}

class ImuConfigPanel extends StatefulWidget {
  final DeviceController controller;

  const ImuConfigPanel({super.key, required this.controller});

  @override
  State<ImuConfigPanel> createState() => _ImuConfigPanelState();
}

class _ImuConfigPanelState extends State<ImuConfigPanel> {
  late ImuSensorConfig _draft;
  late ImuSensorConfig _lastControllerConfig;

  @override
  void initState() {
    super.initState();
    _draft = widget.controller.imuConfig;
    _lastControllerConfig = widget.controller.imuConfig;
  }

  @override
  void didUpdateWidget(covariant ImuConfigPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller.imuConfig != _lastControllerConfig) {
      _draft = widget.controller.imuConfig;
      _lastControllerConfig = widget.controller.imuConfig;
    }
  }

  @override
  Widget build(BuildContext context) {
    final characteristicFound =
        widget.controller.imuConfigCharacteristic != null;
    final applying = widget.controller.isApplyingImuConfig;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "IMU config",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (!characteristicFound)
              const Text("GATT характеристика IMU config не найдена")
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _buildDropdown(
                      label: "ACC ODR",
                      value: _draft.accelOdrHz,
                      suffix: "Hz",
                      options: ImuSensorConfig.odrOptions,
                      onChanged: applying
                          ? null
                          : (value) {
                              setState(
                                () =>
                                    _draft = _draft.copyWith(accelOdrHz: value),
                              );
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDropdown(
                      label: "ACC RANGE",
                      value: _draft.accelRangeG,
                      suffix: "g",
                      options: ImuSensorConfig.accelRangeOptions,
                      onChanged: applying
                          ? null
                          : (value) {
                              setState(
                                () => _draft = _draft.copyWith(
                                  accelRangeG: value,
                                ),
                              );
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildDropdown(
                      label: "GYRO ODR",
                      value: _draft.gyroOdrHz,
                      suffix: "Hz",
                      options: ImuSensorConfig.odrOptions,
                      onChanged: applying
                          ? null
                          : (value) {
                              setState(
                                () =>
                                    _draft = _draft.copyWith(gyroOdrHz: value),
                              );
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDropdown(
                      label: "GYRO RANGE",
                      value: _draft.gyroRangeDps,
                      suffix: "dps",
                      options: ImuSensorConfig.gyroRangeOptions,
                      onChanged: applying
                          ? null
                          : (value) {
                              setState(
                                () => _draft = _draft.copyWith(
                                  gyroRangeDps: value,
                                ),
                              );
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: applying
                        ? null
                        : () => widget.controller.readImuConfig(),
                    child: const Text("Прочитать"),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: applying
                        ? null
                        : () => widget.controller.applyImuConfig(_draft),
                    child: applying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text("Применить"),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required int value,
    required String suffix,
    required List<int> options,
    required ValueChanged<int>? onChanged,
  }) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: options.map((option) {
        return DropdownMenuItem(value: option, child: Text("$option $suffix"));
      }).toList(),
      onChanged: onChanged == null
          ? null
          : (value) {
              if (value != null) onChanged(value);
            },
    );
  }
}

class NotifyTestPanel extends StatelessWidget {
  final DeviceController controller;
  final ThroughputUnit unit;
  final int intervalMs;
  final Duration? duration;

  const NotifyTestPanel({
    super.key,
    required this.controller,
    required this.unit,
    required this.intervalMs,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          "Характеристика для чтения (Notify):",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        if (controller.notifyCharacteristics.isEmpty)
          const Text("Нет доступных характеристик")
        else
          ValueListenableBuilder<bool>(
            valueListenable: controller.isTestingNotifier,
            builder: (context, isTesting, child) {
              return DropdownButton<BluetoothCharacteristic>(
                isExpanded: true,
                value: controller.selectedNotifyCharacteristic,
                items: controller.notifyCharacteristics.map((c) {
                  bool isTargetService =
                      c.serviceUuid.toString() ==
                      "7ec70001-0f5b-4777-ad1d-5add0ac66680";
                  return DropdownMenuItem(
                    value: c,
                    child: Text(
                      "${c.uuid}\n${isTargetService ? '(Target Service)' : ''}",
                      style: TextStyle(
                        fontSize: 12,
                        color: isTargetService ? Colors.blue : null,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: isTesting
                    ? null
                    : (v) {
                        controller.selectNotifyCharacteristic(v);
                      },
              );
            },
          ),
        const SizedBox(height: 20),
        ValueListenableBuilder<bool>(
          valueListenable: controller.isTestingNotifier,
          builder: (context, isTesting, child) {
            return ElevatedButton(
              onPressed: () => controller.toggleNotificationTest(
                unit,
                intervalMs,
                duration: duration,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isTesting
                    ? Colors.red
                    : Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              child: Text(isTesting ? "Остановить тест" : "Старт Notify тест"),
            );
          },
        ),
      ],
    );
  }
}
