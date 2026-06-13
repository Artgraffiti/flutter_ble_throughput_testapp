// ==> lib/screens/device_screen.dart <==
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../controllers/device_controller.dart';
import '../models/throughput_unit.dart';
import '../widgets/test_panels.dart';
import '../widgets/csv_panel.dart';
import '../widgets/theme_mode_menu_button.dart';

class DeviceScreen extends StatefulWidget {
  final BluetoothDevice device;

  const DeviceScreen({super.key, required this.device});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late DeviceController _controller;
  final ScrollController _logScrollController = ScrollController();

  // Локальные состояния UI
  bool _isWriteMode = true;
  ThroughputUnit _selectedUnit = ThroughputUnit.kilobits;
  int _updateIntervalMs = 33;
  int? _selectedTestDurationMinutes;

  Duration? get _selectedTestDuration => _selectedTestDurationMinutes == null
      ? null
      : Duration(minutes: _selectedTestDurationMinutes!);

  // Измерение FPS
  late Ticker _fpsTicker;
  int _frameCount = 0;
  double _currentFps = 0.0;
  DateTime _lastFpsUpdate = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = DeviceController(widget.device);

    _fpsTicker = createTicker((_) {
      _frameCount++;
      final now = DateTime.now();
      if (now.difference(_lastFpsUpdate).inMilliseconds >= 1000) {
        if (mounted) {
          setState(() {
            _currentFps = _frameCount.toDouble();
            _frameCount = 0;
            _lastFpsUpdate = now;
          });
        }
      }
    });
    _fpsTicker.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _controller.disconnect();
    }
  }

  @override
  void dispose() {
    _fpsTicker.dispose();
    _logScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        final isConnected =
            _controller.connectionState == BluetoothConnectionState.connected;
        final isDisconnected =
            _controller.connectionState ==
            BluetoothConnectionState.disconnected;
        final isConnecting = _controller.isConnecting;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.device.platformName.isNotEmpty
                  ? widget.device.platformName
                  : 'Unknown Device',
            ),
            actions: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    'FPS: ${_currentFps.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ),
              const ThemeModeMenuButton(),
              if (isConnected)
                IconButton(
                  icon: const Icon(Icons.bluetooth_disabled),
                  onPressed: () => _controller.disconnect(),
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text('ID: ${widget.device.remoteId}'),
                  Text(
                    'Status: ${_controller.connectionState.toString().split('.').last}',
                  ),

                  if (isConnected && _controller.currentMtu > 0)
                    Text('MTU: ${_controller.currentMtu} bytes'),

                  const SizedBox(height: 20),

                  if (isConnecting)
                    const CircularProgressIndicator()
                  else if (isDisconnected)
                    _buildReconnectButton()
                  else if (isConnected) ...[
                    _buildTopControls(),
                    const SizedBox(height: 20),
                    ImuConfigPanel(controller: _controller),
                    const SizedBox(height: 20),
                    _buildMainPanels(),
                  ],

                  const SizedBox(height: 20),

                  ValueListenableBuilder<String>(
                    valueListenable: _controller.logTextNotifier,
                    builder: (context, logText, child) {
                      return SizedBox(
                        height: 260,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Scrollbar(
                            controller: _logScrollController,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _logScrollController,
                              child: SelectableText(
                                logText,
                                textAlign: TextAlign.left,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReconnectButton() {
    return Column(
      children: [
        const Icon(
          Icons.signal_cellular_connected_no_internet_4_bar,
          size: 64,
          color: Colors.grey,
        ),
        const SizedBox(height: 16),
        const Text(
          "Связь с устройством потеряна",
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => _controller.connect(),
          icon: const Icon(Icons.refresh),
          label: const Text("Переподключиться"),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildTopControls() {
    return Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: _controller.isTestingNotifier,
          builder: (context, isTesting, child) {
            final busy = isTesting || _controller.isAutoTesting;
            return ToggleButtons(
              isSelected: [_isWriteMode, !_isWriteMode],
              onPressed: busy
                  ? null
                  : (index) {
                      setState(() {
                        _isWriteMode = index == 0;
                        _controller.logTextNotifier.value = "";
                      });
                    },
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text("Write Test"),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text("Notify Test"),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Единицы: "),
            const SizedBox(width: 8),
            DropdownButton<ThroughputUnit>(
              value: _selectedUnit,
              items: ThroughputUnit.values
                  .map(
                    (unit) => DropdownMenuItem(
                      value: unit,
                      child: Text(unit.toString().split('.').last),
                    ),
                  )
                  .toList(),
              onChanged:
                  _controller.isAutoTesting ||
                      _controller.isTestingNotifier.value
                  ? null
                  : (v) => setState(() => _selectedUnit = v!),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ValueListenableBuilder<bool>(
          valueListenable: _controller.isTestingNotifier,
          builder: (context, isTesting, child) {
            final busy = isTesting || _controller.isAutoTesting;
            return Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 10,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Интервал UI: "),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _updateIntervalMs,
                      items: const [
                        DropdownMenuItem(
                          value: 16,
                          child: Text("16 мс (~60 FPS)"),
                        ),
                        DropdownMenuItem(
                          value: 33,
                          child: Text("33 мс (~30 FPS)"),
                        ),
                        DropdownMenuItem(value: 50, child: Text("50 мс")),
                        DropdownMenuItem(value: 100, child: Text("100 мс")),
                        DropdownMenuItem(value: 200, child: Text("200 мс")),
                        DropdownMenuItem(value: 500, child: Text("500 мс")),
                      ],
                      onChanged: busy
                          ? null
                          : (v) => setState(() => _updateIntervalMs = v!),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Длительность: "),
                    const SizedBox(width: 8),
                    DropdownButton<int?>(
                      value: _selectedTestDurationMinutes,
                      hint: const Text("Ручной"),
                      items: const [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text("Ручной"),
                        ),
                        DropdownMenuItem(value: 1, child: Text("1 мин")),
                        DropdownMenuItem(value: 5, child: Text("5 мин")),
                        DropdownMenuItem(value: 10, child: Text("10 мин")),
                        DropdownMenuItem(value: 20, child: Text("20 мин")),
                        DropdownMenuItem(value: 30, child: Text("30 мин")),
                        DropdownMenuItem(value: 60, child: Text("60 мин")),
                      ],
                      onChanged: busy
                          ? null
                          : (v) => setState(
                              () => _selectedTestDurationMinutes = v,
                            ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildMainPanels() {
    if (_isWriteMode) {
      return WriteTestPanel(
        controller: _controller,
        unit: _selectedUnit,
        intervalMs: _updateIntervalMs,
        duration: _selectedTestDuration,
      );
    } else {
      return Column(
        children: [
          NotifyTestPanel(
            controller: _controller,
            unit: _selectedUnit,
            intervalMs: _updateIntervalMs,
            duration: _selectedTestDuration,
          ),
          const SizedBox(height: 20),
          const Divider(),
          CsvRecordingPanel(
            csvManager: _controller.csvManager,
            onFormatChanged: () => setState(() {}),
            controlsEnabled: !_controller.isAutoTesting,
          ),
          const SizedBox(height: 20),
          ImuRangeAutoTestPanel(
            controller: _controller,
            unit: _selectedUnit,
            intervalMs: _updateIntervalMs,
            duration: _selectedTestDuration,
          ),
        ],
      );
    }
  }
}
