// ==> lib/controllers/device_controller.dart <==
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/throughput_unit.dart';
import '../models/imu_packet.dart';
import 'csv_manager.dart';

class DeviceController extends ChangeNotifier {
  final BluetoothDevice device;
  late final CsvManager csvManager;

  BluetoothConnectionState connectionState = BluetoothConnectionState.disconnected;
  int currentMtu = 0;
  List<BluetoothCharacteristic> writableCharacteristics = [];
  List<BluetoothCharacteristic> notifyCharacteristics = [];
  
  BluetoothCharacteristic? selectedCharacteristic;
  BluetoothCharacteristic? selectedNotifyCharacteristic;

  final ValueNotifier<String> logTextNotifier = ValueNotifier<String>("");
  final ValueNotifier<bool> isTestingNotifier = ValueNotifier<bool>(false);

  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription? _notifySub;
  Timer? _notifyUpdateTimer;
  final Stopwatch _notifyStopwatch = Stopwatch();

  int _notifyBytesReceived = 0;
  int _notifyPacketCount = 0;
  List<int> _lastPacketData = [];
  DpImuPacket? _lastImuPacket;

  double _instantSpeed = 0;
  double _maxSpeed = 0;
  int _lastBytes = 0;
  double _lastTime = 0;
  final double _speedCalcInterval = 0.5;

  DeviceController(this.device) {
    csvManager = CsvManager(logTextNotifier);
    _init();
  }

  void _init() {
    _connectionSub = device.connectionState.listen((state) {
      connectionState = state;
      notifyListeners();
      if (state == BluetoothConnectionState.connected) {
        _prepareForTest();
      }
    });
    connect();
  }

  Future<void> connect() async {
    // Предотвращаем спам кнопкой подключения
    if (connectionState == BluetoothConnectionState.connecting) return;
    
    try {
      logTextNotifier.value = "Подключение...";
      await device.connect();
    } catch (e) {
      logTextNotifier.value = "Ошибка подключения: $e";
    }
  }

  void disconnect() {
    device.disconnect();
  }

  Future<void> _prepareForTest() async {
    try {
      if (Platform.isAndroid) {
        await device.requestMtu(512);
      }
      currentMtu = await device.mtu.first;
      notifyListeners();

      List<BluetoothService> services = await device.discoverServices();
      List<BluetoothCharacteristic> writable = [];
      List<BluetoothCharacteristic> notifiable = [];

      for (var service in services) {
        for (var c in service.characteristics) {
          if (c.properties.write || c.properties.writeWithoutResponse) writable.add(c);
          if (c.properties.notify || c.properties.indicate) notifiable.add(c);
        }
      }

      writableCharacteristics = writable;
      notifyCharacteristics = notifiable;
      
      if (writable.isNotEmpty) selectedCharacteristic = writable.first;
      if (notifiable.isNotEmpty) {
        try {
          selectedNotifyCharacteristic = notifiable.firstWhere(
            (c) => c.serviceUuid.toString() == "7ec70001-0f5b-4777-ad1d-5add0ac66680",
            orElse: () => notifiable.first
          );
        } catch (_) {
          selectedNotifyCharacteristic = notifiable.first;
        }
      }
      notifyListeners();
    } catch (e) {
      logTextNotifier.value = "Ошибка подготовки: $e";
    }
  }

  Future<void> runWriteTest(ThroughputUnit unit, int updateIntervalMs) async {
    if (selectedCharacteristic == null) return;

    isTestingNotifier.value = true;
    logTextNotifier.value = "Начало теста...";
    _resetMetrics();

    try {
      int packetSize = (currentMtu > 3) ? currentMtu - 3 : 20;
      List<int> data = List.filled(packetSize, 0xAA);
      int packetsToSend = 1000;
      int totalBytes = packetsToSend * packetSize;

      bool withoutResponse = selectedCharacteristic!.properties.writeWithoutResponse;
      String writeType = withoutResponse ? "NoResponse" : "WithResponse";

      Stopwatch stopwatch = Stopwatch()..start();
      int bytesSent = 0;
      double lastUiUpdate = 0;

      for (int i = 0; i < packetsToSend; i++) {
        await selectedCharacteristic!.write(data, withoutResponse: withoutResponse);
        bytesSent += packetSize;

        double now = stopwatch.elapsedMilliseconds / 1000.0;

        if (now - _lastTime >= _speedCalcInterval) {
          _calculateSpeed(now, bytesSent.toDouble());
        }

        if (now - lastUiUpdate >= updateIntervalMs / 1000.0) {
          logTextNotifier.value = "Отправка... ${(i / packetsToSend * 100).toStringAsFixed(0)}%\n"
                                  "Мгновенная: ${unit.formatSpeed(_instantSpeed)}\n"
                                  "Максимальная: ${unit.formatSpeed(_maxSpeed)}";
          lastUiUpdate = now;
        }
      }

      stopwatch.stop();
      double seconds = stopwatch.elapsedMilliseconds / 1000.0;
      double speedBytesPerSec = totalBytes / seconds;

      logTextNotifier.value = "Тип: $writeType\nОтправлено: $totalBytes байт\nВремя: ${seconds.toStringAsFixed(2)} сек\nСредняя: ${unit.formatSpeed(speedBytesPerSec)}\nМаксимальная: ${unit.formatSpeed(_maxSpeed)}";
    } catch (e) {
      logTextNotifier.value = "Ошибка теста: $e";
    } finally {
      isTestingNotifier.value = false;
    }
  }

  Future<void> toggleNotificationTest(ThroughputUnit unit, int updateIntervalMs) async {
    if (selectedNotifyCharacteristic == null) return;

    if (isTestingNotifier.value) {
      _notifyUpdateTimer?.cancel();
      _notifySub?.cancel();
      _notifyStopwatch.stop();

      try {
        await selectedNotifyCharacteristic!.setNotifyValue(false);
      } catch (e) {
        debugPrint("Ошибка отключения уведомлений: $e");
      }

      isTestingNotifier.value = false;
      _updateNotifyStats(unit, finalUpdate: true);
    } else {
      isTestingNotifier.value = true;
      _resetMetrics();
      logTextNotifier.value = "Ожидание данных...";

      try {
        await selectedNotifyCharacteristic!.setNotifyValue(true);
        _notifyStopwatch.reset();
        _notifyStopwatch.start();

        _notifySub = selectedNotifyCharacteristic!.onValueReceived.listen((data) {
          _notifyBytesReceived += data.length;
          _notifyPacketCount++;
          _lastPacketData = data;

          if (selectedNotifyCharacteristic!.uuid.toString() == "7ec70002-0f5b-4777-ad1d-5add0ac66680") {
            _lastImuPacket = DpImuPacket.fromBytes(data);
            if (_lastImuPacket != null) {
              csvManager.writeImuToCsv(_lastImuPacket!);
            }
          }
        });

        _notifyUpdateTimer = Timer.periodic(Duration(milliseconds: updateIntervalMs), (timer) {
          _updateNotifyStats(unit);
        });

      } catch (e) {
        isTestingNotifier.value = false;
        logTextNotifier.value = "Ошибка запуска Notify: $e";
      }
    }
  }

  void _resetMetrics() {
    _notifyBytesReceived = 0;
    _notifyPacketCount = 0;
    _instantSpeed = 0;
    _maxSpeed = 0;
    _lastBytes = 0;
    _lastTime = 0;
    _lastPacketData = [];
    _lastImuPacket = null;
  }

  void _calculateSpeed(double currentTime, double currentBytes) {
    double deltaT = currentTime - _lastTime;
    double deltaBytes = currentBytes - _lastBytes;
    _instantSpeed = deltaBytes / deltaT;
    if (_instantSpeed > _maxSpeed) _maxSpeed = _instantSpeed;
    _lastBytes = currentBytes.toInt();
    _lastTime = currentTime;
  }

  void _updateNotifyStats(ThroughputUnit unit, {bool finalUpdate = false}) {
    double now = _notifyStopwatch.elapsedMilliseconds / 1000.0;
    if (now == 0) return;

    if (now - _lastTime >= _speedCalcInterval || finalUpdate) {
      _calculateSpeed(now, _notifyBytesReceived.toDouble());
    }

    double avgSpeed = _notifyBytesReceived / now;
    String hexData = _lastPacketData.isEmpty
        ? "Нет данных"
        : _lastPacketData.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

    String decodedImuText = "";
    if (_lastImuPacket != null) {
      var imu = _lastImuPacket!.imu[0];
      decodedImuText = "\n\n[Декодированный IMU]\nTimestamp: ${_lastImuPacket!.timestamp} мкс\n"
          "Снапшот 0 (СИ):\n"
          "ACC: x=${imu.accMs2[0].toStringAsFixed(2)}, y=${imu.accMs2[1].toStringAsFixed(2)}, z=${imu.accMs2[2].toStringAsFixed(2)} [m/s^2]\n"
          "GYR: x=${imu.gyroRads[0].toStringAsFixed(2)}, y=${imu.gyroRads[1].toStringAsFixed(2)}, z=${imu.gyroRads[2].toStringAsFixed(2)} [rad/s]\n";
    }

    logTextNotifier.value = "Получено: $_notifyBytesReceived байт\nВремя: ${now.toStringAsFixed(2)} сек\nМгновенная: ${unit.formatSpeed(_instantSpeed)}\nСредняя: ${unit.formatSpeed(avgSpeed)}\nМаксимальная: ${unit.formatSpeed(_maxSpeed)}\n\nПоследний пакет (№$_notifyPacketCount, ${_lastPacketData.length} байт):\n$hexData$decodedImuText";
  }

  @override
  void dispose() {
    csvManager.dispose();
    _connectionSub?.cancel();
    _notifySub?.cancel();
    _notifyUpdateTimer?.cancel();
    logTextNotifier.dispose();
    isTestingNotifier.dispose();
    disconnect();
    super.dispose();
  }
}