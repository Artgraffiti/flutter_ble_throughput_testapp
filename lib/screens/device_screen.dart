// ==> lib/screens/device_screen.dart <==
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/throughput_unit.dart';
import '../models/imu_packet.dart'; 

class DeviceScreen extends StatefulWidget {
  final BluetoothDevice device;

  const DeviceScreen({super.key, required this.device});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
  late StreamSubscription<BluetoothConnectionState> _connectionStateSubscription;
  
  // Переменные для теста
  List<BluetoothCharacteristic> _writableCharacteristics = [];
  List<BluetoothCharacteristic> _notifyCharacteristics = [];
  BluetoothCharacteristic? _selectedCharacteristic;
  BluetoothCharacteristic? _selectedNotifyCharacteristic;
  String _logText = "";
  bool _isTesting = false;
  bool _isNotifyTesting = false;
  bool _isWriteMode = true;
  int _currentMtu = 0;
  ThroughputUnit _selectedUnit = ThroughputUnit.kilobits;
  int _updateIntervalMs = 33; // ~30 FPS для плавности экрана
  
  StreamSubscription? _notifySubscription;
  int _notifyBytesReceived = 0;
  int _notifyPacketCount = 0; // Счетчик пакетов для визуализации
  Timer? _notifyUpdateTimer;
  final Stopwatch _notifyStopwatch = Stopwatch();
  
  List<int> _lastPacketData = [];
  DpImuPacket? _lastImuPacket; // Переменная для хранения разобранных данных IMU

  // Переменные для мгновенной скорости
  double _instantSpeed = 0;
  double _maxSpeed = 0;
  int _lastBytes = 0;
  double _lastTime = 0;
  final double _speedCalcInterval = 0.5; // Считаем скорость жестко раз в 500 мс для стабильности

  // Переменные для FPS
  late Ticker _fpsTicker;
  int _frameCount = 0;
  double _currentFps = 0.0;
  DateTime _lastFpsUpdate = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
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

    _connectionStateSubscription = widget.device.connectionState.listen((state) {
      if (mounted) {
        setState(() {
          _connectionState = state;
          if (state == BluetoothConnectionState.connected) {
            _prepareForTest();
          }
        });
      }
    });

    _connect();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      widget.device.disconnect();
    }
  }

  Future<void> _connect() async {
    try {
      await widget.device.connect();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Ошибка подключения: $e")));
      }
    }
  }

  Future<void> _prepareForTest() async {
    try {
      if (Platform.isAndroid) {
        await widget.device.requestMtu(512);
      }
      var mtu = await widget.device.mtu.first;
      if (mounted) setState(() => _currentMtu = mtu);

      List<BluetoothService> services = await widget.device.discoverServices();

      List<BluetoothCharacteristic> writable = [];
      List<BluetoothCharacteristic> notifiable = [];
      
      for (var service in services) {
        for (var c in service.characteristics) {
          if (c.properties.write || c.properties.writeWithoutResponse) {
            writable.add(c);
          }
          if (c.properties.notify || c.properties.indicate) {
            notifiable.add(c);
          }
        }
      }

      if (mounted) {
        setState(() {
          _writableCharacteristics = writable;
          _notifyCharacteristics = notifiable;
          if (writable.isNotEmpty) {
            _selectedCharacteristic = writable.first;
          }
          if (notifiable.isNotEmpty) {
            try {
              _selectedNotifyCharacteristic = notifiable.firstWhere(
                (c) => c.serviceUuid.toString() == "7ec70001-0f5b-4777-ad1d-5add0ac66680",
                orElse: () => notifiable.first
              );
            } catch (_) {
              _selectedNotifyCharacteristic = notifiable.first;
            }
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _logText = "Ошибка подготовки: $e");
    }
  }

  Future<void> _runThroughputTest() async {
    if (_selectedCharacteristic == null) return;
    
    setState(() {
      _isTesting = true;
      _logText = "Начало теста...";
      _instantSpeed = 0;
      _maxSpeed = 0;
      _lastBytes = 0;
      _lastTime = 0;
    });

    try {
      int packetSize = (_currentMtu > 3) ? _currentMtu - 3 : 20;
      List<int> data = List.filled(packetSize, 0xAA);
      int packetsToSend = 1000;
      int totalBytes = packetsToSend * packetSize;

      bool withoutResponse = _selectedCharacteristic!.properties.writeWithoutResponse;
      String writeType = withoutResponse ? "NoResponse" : "WithResponse";

      Stopwatch stopwatch = Stopwatch()..start();
      int bytesSent = 0;
      double lastUiUpdateTime = 0;

      for (int i = 0; i < packetsToSend; i++) {
        await _selectedCharacteristic!.write(data, withoutResponse: withoutResponse);
        bytesSent += packetSize;

        double now = stopwatch.elapsedMilliseconds / 1000.0;
        
        if (now - _lastTime >= _speedCalcInterval) {
          double deltaT = now - _lastTime;
          double deltaBytes = (bytesSent - _lastBytes).toDouble();
          _instantSpeed = deltaBytes / deltaT;
          if (_instantSpeed > _maxSpeed) _maxSpeed = _instantSpeed;
          _lastBytes = bytesSent;
          _lastTime = now;
        }

        if (now - lastUiUpdateTime >= _updateIntervalMs / 1000.0) {
           if (mounted) {
             setState(() {
               _logText = "Отправка... ${(i / packetsToSend * 100).toStringAsFixed(0)}%\n"
                          "Мгновенная: ${_selectedUnit.formatSpeed(_instantSpeed)}\n"
                          "Максимальная: ${_selectedUnit.formatSpeed(_maxSpeed)}";
             });
           }
           lastUiUpdateTime = now;
        }
      }

      stopwatch.stop();
      
      double seconds = stopwatch.elapsedMilliseconds / 1000.0;
      double speedBytesPerSec = totalBytes / seconds;

      if (mounted) {
        setState(() {
          _logText = "Тип: $writeType\n"
                     "Отправлено: $totalBytes байт\n"
                     "Время: ${seconds.toStringAsFixed(2)} сек\n"
                     "Средняя: ${_selectedUnit.formatSpeed(speedBytesPerSec)}\n"
                     "Максимальная: ${_selectedUnit.formatSpeed(_maxSpeed)}";
        });
      }

    } catch (e) {
      if (mounted) setState(() => _logText = "Ошибка теста: $e");
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _toggleNotificationTest() async {
    if (_selectedNotifyCharacteristic == null) return;

    if (_isNotifyTesting) {
      _notifyUpdateTimer?.cancel();
      _notifySubscription?.cancel();
      _notifyStopwatch.stop();
      
      try {
        await _selectedNotifyCharacteristic!.setNotifyValue(false);
      } catch (e) {
        debugPrint("Ошибка отключения уведомлений: $e");
      }

      if (mounted) {
        setState(() {
          _isNotifyTesting = false;
          _updateNotifyStats(finalUpdate: true);
        });
      }
    } else {
      setState(() {
        _isNotifyTesting = true;
        _notifyBytesReceived = 0;
        _notifyPacketCount = 0;
        _instantSpeed = 0;
        _maxSpeed = 0;
        _lastBytes = 0;
        _lastTime = 0;
        _lastPacketData = [];
        _lastImuPacket = null;
        _logText = "Ожидание данных...";
      });

      try {
        await _selectedNotifyCharacteristic!.setNotifyValue(true);
        
        _notifyStopwatch.reset();
        _notifyStopwatch.start();

        _notifySubscription = _selectedNotifyCharacteristic!.onValueReceived.listen((data) {
          _notifyBytesReceived += data.length;
          _notifyPacketCount++; 
          _lastPacketData = data;

          // Проверяем, что получены данные от IMU характеристики, и парсим их
          if (_selectedNotifyCharacteristic!.uuid.toString() == "7ec70002-0f5b-4777-ad1d-5add0ac66680") {
             _lastImuPacket = DpImuPacket.fromBytes(data);
          }
        });

        _notifyUpdateTimer = Timer.periodic(Duration(milliseconds: _updateIntervalMs), (timer) {
          _updateNotifyStats();
        });

      } catch (e) {
        if (mounted) {
          setState(() {
            _isNotifyTesting = false;
            _logText = "Ошибка запуска Notify: $e";
          });
        }
      }
    }
  }

  void _updateNotifyStats({bool finalUpdate = false}) {
    double now = _notifyStopwatch.elapsedMilliseconds / 1000.0;
    if (now == 0) return;

    double deltaT = now - _lastTime;
    if (deltaT >= _speedCalcInterval || finalUpdate) {
      double deltaBytes = (_notifyBytesReceived - _lastBytes).toDouble();
      _instantSpeed = deltaBytes / deltaT;
      if (_instantSpeed > _maxSpeed) _maxSpeed = _instantSpeed;
      _lastBytes = _notifyBytesReceived;
      _lastTime = now;
    }

    double avgSpeed = _notifyBytesReceived / now;

    String hexData = _lastPacketData.isEmpty 
        ? "Нет данных" 
        : _lastPacketData.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

    String decodedImuText = "";
    if (_lastImuPacket != null) {
      decodedImuText = "\n\n[Декодированный IMU]\nTimestamp: ${_lastImuPacket!.timestamp} мкс\n";
      
      // Выводим только первый снапшот для компактности
      var imu = _lastImuPacket!.imu[0]; 
      
      String ax = imu.accMs2[0].toStringAsFixed(2);
      String ay = imu.accMs2[1].toStringAsFixed(2);
      String az = imu.accMs2[2].toStringAsFixed(2);
      
      String gx = imu.gyroRads[0].toStringAsFixed(2);
      String gy = imu.gyroRads[1].toStringAsFixed(2);
      String gz = imu.gyroRads[2].toStringAsFixed(2);

      decodedImuText += "Снапшот 0 (СИ):\n";
      decodedImuText += "ACC: x=$ax, y=$ay, z=$az [m/s^2]\n";
      decodedImuText += "GYR: x=$gx, y=$gy, z=$gz [rad/s]\n";
    }

    if (mounted) {
      setState(() {
        _logText = "Получено: $_notifyBytesReceived байт\n"
                   "Время: ${now.toStringAsFixed(2)} сек\n"
                   "Мгновенная: ${_selectedUnit.formatSpeed(_instantSpeed)}\n"
                   "Средняя: ${_selectedUnit.formatSpeed(avgSpeed)}\n"
                   "Максимальная: ${_selectedUnit.formatSpeed(_maxSpeed)}\n\n"
                   "Последний пакет (№$_notifyPacketCount, ${_lastPacketData.length} байт):\n$hexData"
                   "$decodedImuText";
      });
    }
  }

  @override
  void dispose() {
    _fpsTicker.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _connectionStateSubscription.cancel();
    _notifySubscription?.cancel();
    _notifyUpdateTimer?.cancel();
    widget.device.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.platformName.isNotEmpty
            ? widget.device.platformName
            : 'Unknown Device'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'FPS: ${_currentFps.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ),
          ),
          if (_connectionState == BluetoothConnectionState.connected)
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              onPressed: () => widget.device.disconnect(),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('ID: ${widget.device.remoteId}'),
              Text('Status: ${_connectionState.toString().split('.').last}'),
              if (_currentMtu > 0) Text('MTU: $_currentMtu bytes'),
              
              const SizedBox(height: 20),
              
              if (_connectionState == BluetoothConnectionState.connecting)
                const CircularProgressIndicator(),

              if (_connectionState == BluetoothConnectionState.connected) ...[
                const SizedBox(height: 20),
                _buildModeSelector(),
                const SizedBox(height: 20),
                _buildUnitSelector(),
                const SizedBox(height: 10),
                _buildIntervalSelector(),
                const SizedBox(height: 20),
                if (_isWriteMode) _buildWriteTestSection() else _buildNotifyTestSection(),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_logText, 
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, fontFamily: 'monospace')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return ToggleButtons(
      isSelected: [_isWriteMode, !_isWriteMode],
      onPressed: (index) {
        if (!_isTesting && !_isNotifyTesting) {
          setState(() {
            _isWriteMode = index == 0;
            _logText = "";
          });
        }
      },
      children: const [
        Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("Write Test")),
        Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("Notify Test")),
      ],
    );
  }

  Widget _buildUnitSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Единицы: "),
        const SizedBox(width: 8),
        DropdownButton<ThroughputUnit>(
          value: _selectedUnit,
          items: const [
            DropdownMenuItem(value: ThroughputUnit.bits, child: Text("бит/с")),
            DropdownMenuItem(value: ThroughputUnit.bytes, child: Text("Байт/с")),
            DropdownMenuItem(value: ThroughputUnit.kilobits, child: Text("Кбит/с")),
            DropdownMenuItem(value: ThroughputUnit.kilobytes, child: Text("Кбайт/с")),
            DropdownMenuItem(value: ThroughputUnit.megabits, child: Text("Мбит/с")),
            DropdownMenuItem(value: ThroughputUnit.megabytes, child: Text("Мбайт/с")),
          ],
          onChanged: (v) => setState(() => _selectedUnit = v!),
        ),
      ],
    );
  }

  Widget _buildIntervalSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Интервал UI: "),
        const SizedBox(width: 8),
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
          onChanged: _isTesting || _isNotifyTesting ? null : (v) => setState(() => _updateIntervalMs = v!),
        ),
      ],
    );
  }

  Widget _buildWriteTestSection() {
    return Column(
      children: [
        const Text("Характеристика для записи:", style: TextStyle(fontWeight: FontWeight.bold)),
        if (_writableCharacteristics.isEmpty)
          const Text("Нет доступных характеристик")
        else
          DropdownButton<BluetoothCharacteristic>(
            isExpanded: true,
            value: _selectedCharacteristic,
            items: _writableCharacteristics.map((c) {
              return DropdownMenuItem(
                value: c,
                child: Text("${c.uuid}\n(Write)", style: const TextStyle(fontSize: 12)),
              );
            }).toList(),
            onChanged: (v) => setState(() => _selectedCharacteristic = v),
          ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _isTesting ? null : _runThroughputTest,
          child: _isTesting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text("Запустить Write тест"),
        ),
      ],
    );
  }

  Widget _buildNotifyTestSection() {
    return Column(
      children: [
        const Text("Характеристика для чтения (Notify):", style: TextStyle(fontWeight: FontWeight.bold)),
        if (_notifyCharacteristics.isEmpty)
          const Text("Нет доступных характеристик")
        else
          DropdownButton<BluetoothCharacteristic>(
            isExpanded: true,
            value: _selectedNotifyCharacteristic,
            items: _notifyCharacteristics.map((c) {
              bool isTargetService = c.serviceUuid.toString() == "7ec70001-0f5b-4777-ad1d-5add0ac66680";
              return DropdownMenuItem(
                value: c,
                child: Text(
                    "${c.uuid}\n${isTargetService ? '(Target Service)' : ''}",
                    style: TextStyle(fontSize: 12, color: isTargetService ? Colors.blue : null)
                ),
              );
            }).toList(),
            onChanged: _isNotifyTesting ? null : (v) => setState(() => _selectedNotifyCharacteristic = v),
          ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _toggleNotificationTest,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isNotifyTesting ? Colors.red : Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
          ),
          child: Text(_isNotifyTesting ? "Остановить тест" : "Старт Notify тест"),
        ),
      ],
    );
  }
}