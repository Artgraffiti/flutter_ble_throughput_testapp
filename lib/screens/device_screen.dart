import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../controllers/device_controller.dart';
import '../models/throughput_unit.dart';
import '../widgets/test_panels.dart';
import '../widgets/csv_panel.dart';

class DeviceScreen extends StatefulWidget {
  final BluetoothDevice device;
  const DeviceScreen({super.key, required this.device});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  late DeviceController _controller;

  bool _isWriteMode = true;
  ThroughputUnit _selectedUnit = ThroughputUnit.kilobits;
  int _updateIntervalMs = 33;

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
    if (state == AppLifecycleState.detached) _controller.disconnect();
  }

  @override
  void dispose() {
    _fpsTicker.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.device.platformName.isNotEmpty ? widget.device.platformName : 'Unknown Device'),
            actions: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text('FPS: ${_currentFps.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                ),
              ),
              if (_controller.connectionState == BluetoothConnectionState.connected)
                IconButton(icon: const Icon(Icons.bluetooth_disabled), onPressed: () => _controller.disconnect()),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: Column(
                children: [
                  Text('ID: ${widget.device.remoteId}'),
                  Text('Status: ${_controller.connectionState.toString().split('.').last}'),
                  if (_controller.currentMtu > 0) Text('MTU: ${_controller.currentMtu} bytes'),
                  const SizedBox(height: 20),
                  
                  if (_controller.connectionState == BluetoothConnectionState.connecting)
                    const CircularProgressIndicator(),

                  if (_controller.connectionState == BluetoothConnectionState.connected) ...[
                    _buildTopControls(),
                    const SizedBox(height: 20),
                    
                    if (_isWriteMode) 
                      WriteTestPanel(controller: _controller, unit: _selectedUnit, intervalMs: _updateIntervalMs)
                    else 
                      Column(
                        children: [
                          NotifyTestPanel(controller: _controller, unit: _selectedUnit, intervalMs: _updateIntervalMs),
                          const SizedBox(height: 20), const Divider(),
                          CsvRecordingPanel(csvManager: _controller.csvManager, onFormatChanged: () => setState((){})),
                        ],
                      ),
                      
                    const SizedBox(height: 20),
                    
                    ValueListenableBuilder<String>(
                      valueListenable: _controller.logTextNotifier,
                      builder: (context, logText, child) => Container(
                        width: double.infinity, padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                        child: Text(logText, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontFamily: 'monospace')),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }
    );
  }

  Widget _buildTopControls() {
    return Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: _controller.isTestingNotifier,
          builder: (context, isTesting, child) => ToggleButtons(
            isSelected: [_isWriteMode, !_isWriteMode],
            onPressed: isTesting ? null : (i) => setState(() { _isWriteMode = i == 0; _controller.logTextNotifier.value = ""; }),
            children: const [
              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("Write Test")),
              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("Notify Test")),
            ],
          )
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Единицы: "), const SizedBox(width: 8),
            DropdownButton<ThroughputUnit>(
              value: _selectedUnit,
              items: ThroughputUnit.values.map((u) => DropdownMenuItem(value: u, child: Text(u.toString().split('.').last))).toList(),
              onChanged: (v) => setState(() => _selectedUnit = v!),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ValueListenableBuilder<bool>(
          valueListenable: _controller.isTestingNotifier,
          builder: (context, isTesting, child) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Интервал UI: "), const SizedBox(width: 8),
              DropdownButton<int>(
                value: _updateIntervalMs,
                items: const [
                  DropdownMenuItem(value: 16, child: Text("16 мс (~60 FPS)")),
                  DropdownMenuItem(value: 33, child: Text("33 мс (~30 FPS)")),
                  DropdownMenuItem(value: 50, child: Text("50 мс")),
                  DropdownMenuItem(value: 100, child: Text("100 мс")),
                  DropdownMenuItem(value: 200, child: Text("200 мс")),
                  DropdownMenuItem(value: 500, child: Text("500 мс")),
                ],
                onChanged: isTesting ? null : (v) => setState(() => _updateIntervalMs = v!),
              ),
            ],
          )
        ),
      ],
    );
  }
}