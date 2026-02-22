import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

enum ThroughputUnit {
  bits,
  bytes,
  kilobits,
  kilobytes,
  megabits,
  megabytes;

  String formatSpeed(double bytesPerSec) {
    switch (this) {
      case ThroughputUnit.bits:
        return "${(bytesPerSec * 8).toStringAsFixed(0)} бит/с";
      case ThroughputUnit.bytes:
        return "${bytesPerSec.toStringAsFixed(0)} Байт/с";
      case ThroughputUnit.kilobits:
        return "${((bytesPerSec * 8) / 1000).toStringAsFixed(2)} Кбит/с";
      case ThroughputUnit.kilobytes:
        return "${(bytesPerSec / 1024).toStringAsFixed(2)} Кбайт/с";
      case ThroughputUnit.megabits:
        return "${((bytesPerSec * 8) / 1000000).toStringAsFixed(2)} Мбит/с";
      case ThroughputUnit.megabytes:
        return "${(bytesPerSec / (1024 * 1024)).toStringAsFixed(2)} Мбайт/с";
    }
  }
}

class DeviceScreen extends StatefulWidget {
  final BluetoothDevice device;

  const DeviceScreen({super.key, required this.device});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> with WidgetsBindingObserver {
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
  int _updateIntervalMs = 500;
  
  StreamSubscription? _notifySubscription;
  int _notifyBytesReceived = 0;
  Timer? _notifyUpdateTimer;
  final Stopwatch _notifyStopwatch = Stopwatch();

  // Переменные для мгновенной скорости
  double _instantSpeed = 0;
  double _maxSpeed = 0;
  int _lastBytes = 0;
  double _lastTime = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectionStateSubscription = widget.device.connectionState.listen((state) {
      setState(() {
        _connectionState = state;
        if (state == BluetoothConnectionState.connected) {
          _prepareForTest();
        }
      });
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
      setState(() => _currentMtu = mtu);

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
    } catch (e) {
      setState(() => _logText = "Ошибка подготовки: $e");
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
      int packetsToSend = 500; // Увеличил кол-во пакетов, чтобы успеть увидеть мгновенную скорость
      int totalBytes = packetsToSend * packetSize;

      bool withoutResponse = _selectedCharacteristic!.properties.writeWithoutResponse;
      String writeType = withoutResponse ? "NoResponse" : "WithResponse";

      Stopwatch stopwatch = Stopwatch()..start();
      int bytesSent = 0;

      for (int i = 0; i < packetsToSend; i++) {
        await _selectedCharacteristic!.write(data, withoutResponse: withoutResponse);
        bytesSent += packetSize;

        // Обновляем мгновенную скорость каждые ~20 пакетов
        if (i % 20 == 0) {
           double now = stopwatch.elapsedMilliseconds / 1000.0;
           if (now - _lastTime >= _updateIntervalMs / 1000.0) {
             double deltaT = now - _lastTime;
             double deltaBytes = (bytesSent - _lastBytes).toDouble();
             
             setState(() {
               _instantSpeed = deltaBytes / deltaT;
               if (_instantSpeed > _maxSpeed) _maxSpeed = _instantSpeed;
               _logText = "Отправка... ${(i / packetsToSend * 100).toStringAsFixed(0)}%\n"
                          "Мгновенная: ${_selectedUnit.formatSpeed(_instantSpeed)}\n"
                          "Максимальная: ${_selectedUnit.formatSpeed(_maxSpeed)}";
             });
             
             _lastBytes = bytesSent;
             _lastTime = now;
           }
        }
      }

      stopwatch.stop();
      
      double seconds = stopwatch.elapsedMilliseconds / 1000.0;
      double speedBytesPerSec = totalBytes / seconds;

      setState(() {
        _logText = "Тип: $writeType\n"
                   "Отправлено: $totalBytes байт\n"
                   "Время: ${seconds.toStringAsFixed(2)} сек\n"
                   "Средняя: ${_selectedUnit.formatSpeed(speedBytesPerSec)}\n"
                   "Максимальная: ${_selectedUnit.formatSpeed(_maxSpeed)}";
      });

    } catch (e) {
      setState(() => _logText = "Ошибка теста: $e");
    } finally {
      setState(() => _isTesting = false);
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

      setState(() {
        _isNotifyTesting = false;
        _updateNotifyStats(finalUpdate: true);
      });
    } else {
      setState(() {
        _isNotifyTesting = true;
        _notifyBytesReceived = 0;
        _instantSpeed = 0;
        _maxSpeed = 0;
        _lastBytes = 0;
        _lastTime = 0;
        _logText = "Ожидание данных...";
      });

      try {
        await _selectedNotifyCharacteristic!.setNotifyValue(true);
        
        _notifyStopwatch.reset();
        _notifyStopwatch.start();

        _notifySubscription = _selectedNotifyCharacteristic!.onValueReceived.listen((data) {
          _notifyBytesReceived += data.length;
        });

        _notifyUpdateTimer = Timer.periodic(Duration(milliseconds: _updateIntervalMs), (timer) {
          _updateNotifyStats();
        });

      } catch (e) {
        setState(() {
          _isNotifyTesting = false;
          _logText = "Ошибка запуска Notify: $e";
        });
      }
    }
  }

  void _updateNotifyStats({bool finalUpdate = false}) {
    double now = _notifyStopwatch.elapsedMilliseconds / 1000.0;
    if (now == 0) return;

    // Расчет мгновенной скорости
    double deltaT = now - _lastTime;
    if (deltaT > 0) {
      double deltaBytes = (_notifyBytesReceived - _lastBytes).toDouble();
      _instantSpeed = deltaBytes / deltaT;
      if (_instantSpeed > _maxSpeed) _maxSpeed = _instantSpeed;
      _lastBytes = _notifyBytesReceived;
      _lastTime = now;
    }

    double avgSpeed = _notifyBytesReceived / now;

    setState(() {
      _logText = "Получено: $_notifyBytesReceived байт\n"
                 "Время: ${now.toStringAsFixed(2)} сек\n"
                 "Мгновенная: ${_selectedUnit.formatSpeed(_instantSpeed)}\n"
                 "Средняя: ${_selectedUnit.formatSpeed(avgSpeed)}\n"
                 "Максимальная: ${_selectedUnit.formatSpeed(_maxSpeed)}";
    });
  }

  @override
  void dispose() {
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
                const SizedBox(height: 20),
                _buildIntervalSelector(),
                const SizedBox(height: 20),
                if (_isWriteMode) _buildWriteTestSection() else _buildNotifyTestSection(),
                const SizedBox(height: 20),
                Text(_logText, 
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16)),
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
        const Text("Интервал обновления: "),
        DropdownButton<int>(
          value: _updateIntervalMs,
          items: const [
            DropdownMenuItem(value: 100, child: Text("100 мс")),
            DropdownMenuItem(value: 200, child: Text("200 мс")),
            DropdownMenuItem(value: 500, child: Text("500 мс")),
            DropdownMenuItem(value: 1000, child: Text("1 сек")),
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
              ? const CircularProgressIndicator(color: Colors.white)
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