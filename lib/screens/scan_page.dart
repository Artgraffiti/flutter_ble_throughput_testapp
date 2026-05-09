import 'dart:async';
import 'dart:io';

import 'package:ble_throughput/screens/device_screen.dart';
import 'package:ble_throughput/widgets/scan_result_tile.dart';
import 'package:ble_throughput/widgets/theme_mode_menu_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  // Список найденных устройств будет приходить через Stream
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;
  late StreamSubscription<BluetoothAdapterState> _adapterStateSubscription;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;

  @override
  void initState() {
    super.initState();
    _setupStreams();
    _checkPermissions();
  }

  void _setupStreams() {
    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _scanResults = results;
      });
    });

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      setState(() {
        _isScanning = state;
      });
    });

    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      setState(() {
        _adapterState = state;
      });
    });
  }

  Future<void> _checkPermissions() async {
    if (Platform.isAndroid) {
      // Для Android 12+ нужны специфические разрешения
      await [
        Permission.location,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
    } else if (Platform.isWindows) {
      // На Windows разрешения управляются системой, но полезно знать, что мы тут
      debugPrint(
        "Запущено на Windows. Проверьте, что Bluetooth включен в настройках ПК.",
      );
    }
  }

  Future<void> _startScan() async {
    try {
      // Очищаем предыдущие результаты перед новым сканированием
      // (опционально, зависит от желаемого поведения)
      // await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      // Но лучше просто запустить сканирование, библиотека сама управляет списком
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      debugPrint("Ошибка запуска сканирования: $e");
    }
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  @override
  void dispose() {
    _scanResultsSubscription.cancel();
    _isScanningSubscription.cancel();
    _adapterStateSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Scanner'),
        actions: const [ThemeModeMenuButton()],
      ),
      body: Column(
        children: [
          if (_adapterState == BluetoothAdapterState.off)
            Container(
              width: double.infinity,
              color: Colors.redAccent,
              padding: const EdgeInsets.all(8.0),
              child: const Text(
                "Bluetooth выключен. Включите его в настройках системы.",
                style: TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                if (_isScanning) {
                  await _stopScan();
                }
                await _startScan();
              },
              child: ListView.separated(
                itemCount: _scanResults.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final result = _scanResults[index];
                  final device = result.device;
                  return ScanResultTile(
                    result: result,
                    onTap: () {
                      _stopScan();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => DeviceScreen(device: device),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isScanning ? _stopScan : _startScan,
        backgroundColor: _isScanning ? colors.error : colors.primary,
        foregroundColor: _isScanning ? colors.onError : colors.onPrimary,
        child: Icon(_isScanning ? Icons.stop : Icons.search),
      ),
    );
  }
}
