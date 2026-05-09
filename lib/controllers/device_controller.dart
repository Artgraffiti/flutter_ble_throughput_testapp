// ==> lib/controllers/device_controller.dart <==
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/throughput_unit.dart';
import '../models/imu_packet.dart';
import '../models/imu_sensor_config.dart';
import 'csv_manager.dart';

class DeviceController extends ChangeNotifier {
  static const String _dpServiceUuid = "7ec70001-0f5b-4777-ad1d-5add0ac66680";
  static const String _dpImuUuid = "7ec70002-0f5b-4777-ad1d-5add0ac66680";
  static const String _dpCommandUuid = "7ec70003-0f5b-4777-ad1d-5add0ac66680";
  static const String _dpImuConfigUuid = "7ec70005-0f5b-4777-ad1d-5add0ac66680";

  final BluetoothDevice device;
  late final CsvManager csvManager;

  BluetoothConnectionState connectionState =
      BluetoothConnectionState.disconnected;
  bool isConnecting = false;
  int currentMtu = 0;
  List<BluetoothCharacteristic> writableCharacteristics = [];
  List<BluetoothCharacteristic> notifyCharacteristics = [];

  BluetoothCharacteristic? selectedCharacteristic;
  BluetoothCharacteristic? selectedNotifyCharacteristic;
  BluetoothCharacteristic? imuConfigCharacteristic;
  ImuSensorConfig imuConfig = ImuSensorConfig.defaults;
  bool isApplyingImuConfig = false;
  bool isAutoTesting = false;

  final ValueNotifier<String> logTextNotifier = ValueNotifier<String>("");
  final ValueNotifier<bool> isTestingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> telemetryNotifier = ValueNotifier<int>(0);

  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription? _notifySub;
  Timer? _notifyUpdateTimer;
  Timer? _testDurationTimer;
  final Stopwatch _notifyStopwatch = Stopwatch();
  Duration? _activeNotifyDuration;
  bool _autoTestCancelRequested = false;
  String _autoTestProgressText = "";

  int _notifyBytesReceived = 0;
  int _notifyPacketCount = 0;
  int _decodedImuPacketCount = 0;
  int _invalidImuPacketCount = 0;
  int _lastInvalidImuPacketLength = 0;
  List<int> _lastPacketData = [];
  List<int>? _latestNotifyData;
  DpImuPacket? _lastImuPacket;

  DpImuPacket? get lastImuPacket => _lastImuPacket;

  double _instantSpeed = 0;
  double _maxSpeed = 0;
  int _lastBytes = 0;
  double _lastTime = 0;
  final double _speedCalcInterval = 0.5;

  DeviceController(this.device) {
    csvManager = CsvManager(
      logTextNotifier,
      imuConfigProvider: () => imuConfig,
    );
    _init();
  }

  void _init() {
    _connectionSub = device.connectionState.listen((state) {
      connectionState = state;
      if (state == BluetoothConnectionState.connected ||
          state == BluetoothConnectionState.disconnected) {
        isConnecting = false;
      }
      notifyListeners();
      if (state == BluetoothConnectionState.connected) {
        _prepareForTest();
      }
    });
    connect();
  }

  Future<void> connect() async {
    // Предотвращаем спам кнопкой подключения
    if (isConnecting) return;

    try {
      isConnecting = true;
      logTextNotifier.value = "Подключение...";
      notifyListeners();
      await device.connect();
    } catch (e) {
      logTextNotifier.value = "Ошибка подключения: $e";
      isConnecting = false;
      notifyListeners();
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
          if (c.properties.write || c.properties.writeWithoutResponse) {
            writable.add(c);
          }
          if (c.properties.notify || c.properties.indicate) notifiable.add(c);
        }
      }

      writableCharacteristics = writable;
      notifyCharacteristics = notifiable;

      if (writable.isNotEmpty) {
        selectedCharacteristic = writable.firstWhere(
          (c) => c.uuid.toString() == _dpCommandUuid,
          orElse: () => writable.first,
        );
      }
      if (notifiable.isNotEmpty) {
        try {
          selectedNotifyCharacteristic = notifiable.firstWhere(
            (c) => c.uuid.toString() == _dpImuUuid,
            orElse: () => notifiable.first,
          );
        } catch (_) {
          selectedNotifyCharacteristic = notifiable.first;
        }
      }

      for (var service in services) {
        if (service.uuid.toString() != _dpServiceUuid) continue;

        for (var c in service.characteristics) {
          if (c.uuid.toString() == _dpImuConfigUuid) {
            imuConfigCharacteristic = c;
            await readImuConfig();
            break;
          }
        }
      }

      notifyListeners();
    } catch (e) {
      logTextNotifier.value = "Ошибка подготовки: $e";
    }
  }

  Future<void> readImuConfig() async {
    final characteristic = imuConfigCharacteristic;
    if (characteristic == null) return;

    try {
      final data = await characteristic.read();
      imuConfig = ImuSensorConfig.fromBytes(data);
      notifyListeners();
    } catch (e) {
      logTextNotifier.value = "Ошибка чтения IMU config: $e";
    }
  }

  void selectWriteCharacteristic(BluetoothCharacteristic? characteristic) {
    selectedCharacteristic = characteristic;
    notifyListeners();
  }

  void selectNotifyCharacteristic(BluetoothCharacteristic? characteristic) {
    selectedNotifyCharacteristic = characteristic;
    notifyListeners();
  }

  Future<bool> applyImuConfig(ImuSensorConfig config) async {
    final characteristic = imuConfigCharacteristic;
    if (characteristic == null) {
      logTextNotifier.value = "IMU config характеристика не найдена";
      return false;
    }

    if (config == imuConfig) {
      return true;
    }

    isApplyingImuConfig = true;
    notifyListeners();

    try {
      await characteristic.write(config.toBytes(), withoutResponse: false);
      imuConfig = config;
      logTextNotifier.value =
          "IMU config применён: ACC ${config.accelOdrHz} Hz / ${config.accelRangeG} g, "
          "GYRO ${config.gyroOdrHz} Hz / ${config.gyroRangeDps} dps";
      await readImuConfig();
      return true;
    } catch (e) {
      logTextNotifier.value = "Ошибка записи IMU config: $e";
      return false;
    } finally {
      isApplyingImuConfig = false;
      notifyListeners();
    }
  }

  Future<void> runWriteTest(
    ThroughputUnit unit,
    int updateIntervalMs, {
    Duration? duration,
  }) async {
    if (selectedCharacteristic == null) return;

    isTestingNotifier.value = true;
    logTextNotifier.value = "Начало теста...";
    _resetMetrics();

    try {
      int packetSize = (currentMtu > 3) ? currentMtu - 3 : 20;
      List<int> data = List.filled(packetSize, 0xAA);
      int packetsToSend = 1000;

      bool withoutResponse =
          selectedCharacteristic!.properties.writeWithoutResponse;
      String writeType = withoutResponse ? "NoResponse" : "WithResponse";

      Stopwatch stopwatch = Stopwatch()..start();
      int bytesSent = 0;
      int packetsSent = 0;
      double lastUiUpdate = 0;
      final durationSeconds = duration?.inMilliseconds == null
          ? null
          : duration!.inMilliseconds / 1000.0;

      while (duration == null || stopwatch.elapsed < duration) {
        if (duration == null && packetsSent >= packetsToSend) break;

        await selectedCharacteristic!.write(
          data,
          withoutResponse: withoutResponse,
        );
        bytesSent += packetSize;
        packetsSent++;

        double now = stopwatch.elapsedMilliseconds / 1000.0;

        if (now - _lastTime >= _speedCalcInterval) {
          _calculateSpeed(now, bytesSent.toDouble());
        }

        if (now - lastUiUpdate >= updateIntervalMs / 1000.0) {
          final progress = durationSeconds == null
              ? packetsSent / packetsToSend
              : (now / durationSeconds).clamp(0.0, 1.0);
          logTextNotifier.value =
              "Отправка... ${(progress * 100).toStringAsFixed(0)}%\n"
              "Пакетов: $packetsSent\n"
              "Мгновенная: ${unit.formatSpeed(_instantSpeed)}\n"
              "Максимальная: ${unit.formatSpeed(_maxSpeed)}";
          lastUiUpdate = now;
        }
      }

      stopwatch.stop();
      double seconds = stopwatch.elapsedMilliseconds / 1000.0;
      double speedBytesPerSec = bytesSent / seconds;

      logTextNotifier.value =
          "Тип: $writeType\nОтправлено: $bytesSent байт\nПакетов: $packetsSent\nВремя: ${seconds.toStringAsFixed(2)} сек\nСредняя: ${unit.formatSpeed(speedBytesPerSec)}\nМаксимальная: ${unit.formatSpeed(_maxSpeed)}";
    } catch (e) {
      logTextNotifier.value = "Ошибка теста: $e";
    } finally {
      isTestingNotifier.value = false;
    }
  }

  Future<void> toggleNotificationTest(
    ThroughputUnit unit,
    int updateIntervalMs, {
    Duration? duration,
  }) async {
    if (selectedNotifyCharacteristic == null || isAutoTesting) return;

    if (isTestingNotifier.value) {
      await _stopNotificationTest(unit);
    } else {
      await _startNotificationTest(
        unit,
        updateIntervalMs,
        duration: duration,
        scheduleStop: true,
      );
    }
  }

  Future<bool> _startNotificationTest(
    ThroughputUnit unit,
    int updateIntervalMs, {
    Duration? duration,
    required bool scheduleStop,
  }) async {
    if (selectedNotifyCharacteristic == null || isTestingNotifier.value) {
      return false;
    }

    isTestingNotifier.value = true;
    _resetMetrics();
    _activeNotifyDuration = duration;
    logTextNotifier.value = "Ожидание данных...";

    try {
      await selectedNotifyCharacteristic!.setNotifyValue(true);
      _notifyStopwatch.reset();
      _notifyStopwatch.start();

      _notifySub = selectedNotifyCharacteristic!.onValueReceived.listen((data) {
        _notifyBytesReceived += data.length;
        _notifyPacketCount++;
        _lastPacketData = data;

        if (selectedNotifyCharacteristic?.uuid.toString() == _dpImuUuid) {
          if (csvManager.isRecording) {
            _decodeImuPacket(data, writeCsv: true);
          } else {
            _latestNotifyData = data;
          }
        }
      });

      _notifyUpdateTimer = Timer.periodic(
        Duration(milliseconds: updateIntervalMs),
        (timer) {
          _updateNotifyStats(unit);
        },
      );

      if (duration != null && scheduleStop) {
        _testDurationTimer = Timer(duration, () {
          _stopNotificationTest(unit);
        });
      }

      return true;
    } catch (e) {
      _testDurationTimer?.cancel();
      _testDurationTimer = null;
      _activeNotifyDuration = null;
      isTestingNotifier.value = false;
      logTextNotifier.value = "Ошибка запуска Notify: $e";
      return false;
    }
  }

  Future<void> _stopNotificationTest(ThroughputUnit unit) async {
    _testDurationTimer?.cancel();
    _testDurationTimer = null;
    _activeNotifyDuration = null;
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
  }

  Future<void> runImuRangeAutoTest(
    ThroughputUnit unit,
    int updateIntervalMs, {
    required Duration? duration,
  }) async {
    if (isAutoTesting || isTestingNotifier.value || isApplyingImuConfig) {
      return;
    }
    if (duration == null) {
      logTextNotifier.value =
          "Для автотеста выберите фиксированную длительность.";
      return;
    }
    if (selectedNotifyCharacteristic == null ||
        selectedNotifyCharacteristic!.uuid.toString() != _dpImuUuid) {
      logTextNotifier.value =
          "Для автотеста выберите IMU Notify характеристику";
      return;
    }
    if (imuConfigCharacteristic == null) {
      logTextNotifier.value = "IMU config характеристика не найдена";
      return;
    }
    if (csvManager.saveDirectory == null) {
      logTextNotifier.value = "Для автотеста выберите папку CSV.";
      return;
    }
    if (csvManager.isRecording) {
      logTextNotifier.value = "Остановите текущую CSV запись перед автотестом.";
      return;
    }

    final originalConfig = imuConfig;
    final steps = _buildImuRangeAutoTestSteps(originalConfig);
    _autoTestCancelRequested = false;
    isAutoTesting = true;
    notifyListeners();

    try {
      for (var index = 0; index < steps.length; index++) {
        if (_autoTestCancelRequested) break;

        final step = steps[index];
        _updateAutoTestProgress(
          stepIndex: index,
          totalSteps: steps.length,
          stepTitle: step.title,
          stepProgress: 0,
        );

        final applied = await applyImuConfig(step.config);
        if (!applied || _autoTestCancelRequested) break;

        await Future<void>.delayed(const Duration(milliseconds: 150));
        if (_autoTestCancelRequested) break;

        final csvStarted = await csvManager.startCsvRecording(
          config: step.config,
          label: step.filenameLabel,
        );
        if (!csvStarted || _autoTestCancelRequested) break;

        final notifyStarted = await _startNotificationTest(
          unit,
          updateIntervalMs,
          duration: duration,
          scheduleStop: false,
        );
        if (!notifyStarted) {
          await csvManager.stopCsvRecording();
          break;
        }

        await _waitAutoTestDuration(
          duration,
          stepIndex: index,
          totalSteps: steps.length,
          stepTitle: step.title,
        );
        await _stopNotificationTest(unit);
        await csvManager.stopCsvRecording();
      }
    } finally {
      if (isTestingNotifier.value) {
        await _stopNotificationTest(unit);
      }
      if (csvManager.isRecording) {
        await csvManager.stopCsvRecording();
      }

      await applyImuConfig(originalConfig);
      isAutoTesting = false;
      _autoTestCancelRequested = false;
      _autoTestProgressText = "";
      notifyListeners();

      logTextNotifier.value =
          "Автотест завершён. Исходные настройки IMU восстановлены.";
    }
  }

  void stopImuRangeAutoTest() {
    _autoTestCancelRequested = true;
    logTextNotifier.value = "Остановка автотеста...";
  }

  void _updateAutoTestProgress({
    required int stepIndex,
    required int totalSteps,
    required String stepTitle,
    required double stepProgress,
  }) {
    final clampedStepProgress = stepProgress.clamp(0.0, 1.0);
    final totalProgress = ((stepIndex + clampedStepProgress) / totalSteps)
        .clamp(0.0, 1.0);
    _autoTestProgressText =
        "Автотест: ${(totalProgress * 100).toStringAsFixed(1)}%\n"
        "Шаг ${stepIndex + 1}/$totalSteps: $stepTitle "
        "(${(clampedStepProgress * 100).toStringAsFixed(0)}%)";
    logTextNotifier.value = _autoTestProgressText;
  }

  List<_ImuRangeAutoTestStep> _buildImuRangeAutoTestSteps(
    ImuSensorConfig baseConfig,
  ) {
    final steps = <_ImuRangeAutoTestStep>[];
    final seenConfigs = <String>{};

    void addStep(_ImuRangeAutoTestStep step) {
      final key = '${step.config.accelRangeG}:${step.config.gyroRangeDps}';
      if (seenConfigs.add(key)) {
        steps.add(step);
      }
    }

    for (final range in ImuSensorConfig.accelRangeOptions) {
      addStep(
        _ImuRangeAutoTestStep(
          title: 'ACC range $range g',
          filenameLabel: 'auto_acc_${range}g',
          config: baseConfig.copyWith(accelRangeG: range),
        ),
      );
    }

    for (final range in ImuSensorConfig.gyroRangeOptions) {
      addStep(
        _ImuRangeAutoTestStep(
          title: 'GYRO range $range dps',
          filenameLabel: 'auto_gyro_${range}dps',
          config: baseConfig.copyWith(gyroRangeDps: range),
        ),
      );
    }

    return steps;
  }

  Future<void> _waitAutoTestDuration(
    Duration duration, {
    required int stepIndex,
    required int totalSteps,
    required String stepTitle,
  }) async {
    final stopwatch = Stopwatch()..start();

    while (!_autoTestCancelRequested && stopwatch.elapsed < duration) {
      _updateAutoTestProgress(
        stepIndex: stepIndex,
        totalSteps: totalSteps,
        stepTitle: stepTitle,
        stepProgress: stopwatch.elapsedMilliseconds / duration.inMilliseconds,
      );

      final remaining = duration - stopwatch.elapsed;
      final delay = remaining > const Duration(milliseconds: 250)
          ? const Duration(milliseconds: 250)
          : remaining;
      await Future<void>.delayed(delay);
    }

    _updateAutoTestProgress(
      stepIndex: stepIndex,
      totalSteps: totalSteps,
      stepTitle: stepTitle,
      stepProgress: 1,
    );
  }

  void _resetMetrics() {
    _notifyBytesReceived = 0;
    _notifyPacketCount = 0;
    _decodedImuPacketCount = 0;
    _invalidImuPacketCount = 0;
    _lastInvalidImuPacketLength = 0;
    _instantSpeed = 0;
    _maxSpeed = 0;
    _lastBytes = 0;
    _lastTime = 0;
    _lastPacketData = [];
    _latestNotifyData = null;
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

    final latestData = _latestNotifyData;
    if (latestData != null) {
      _decodeImuPacket(latestData, writeCsv: false);
      _latestNotifyData = null;
    }
    if (_lastImuPacket != null) {
      telemetryNotifier.value++;
    }

    if (now - _lastTime >= _speedCalcInterval || finalUpdate) {
      _calculateSpeed(now, _notifyBytesReceived.toDouble());
    }

    double avgSpeed = _notifyBytesReceived / now;
    final durationText = _activeNotifyDuration == null
        ? ""
        : "\nДлительность теста: ${_activeNotifyDuration!.inMinutes} мин";
    String hexData = _lastPacketData.isEmpty
        ? "Нет данных"
        : _lastPacketData
              .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
              .join(' ');

    String decodedImuText = "";
    if (_lastImuPacket != null) {
      var imu = _lastImuPacket!.imu[0];
      decodedImuText =
          "\n\n[Декодированный IMU]\nTimestamp: ${_lastImuPacket!.timestamp} мкс\n"
          "Декодировано IMU-пакетов: $_decodedImuPacketCount\n"
          "Некорректных notify: $_invalidImuPacketCount"
          "${_lastInvalidImuPacketLength > 0 ? ' (последняя длина $_lastInvalidImuPacketLength байт)' : ''}\n"
          "Снапшот 0 (СИ, ACC ±${_lastImuPacket!.config.accelRangeG}g, GYRO ±${_lastImuPacket!.config.gyroRangeDps}dps):\n"
          "ACC: x=${imu.accMs2[0].toStringAsFixed(2)}, y=${imu.accMs2[1].toStringAsFixed(2)}, z=${imu.accMs2[2].toStringAsFixed(2)} [m/s^2]\n"
          "GYR: x=${imu.gyroRads[0].toStringAsFixed(2)}, y=${imu.gyroRads[1].toStringAsFixed(2)}, z=${imu.gyroRads[2].toStringAsFixed(2)} [rad/s]\n";
    }

    final autoTestPrefix = _autoTestProgressText.isEmpty
        ? ""
        : "$_autoTestProgressText\n\n";
    logTextNotifier.value =
        "$autoTestPrefixПолучено: $_notifyBytesReceived байт\nВремя: ${now.toStringAsFixed(2)} сек$durationText\nМгновенная: ${unit.formatSpeed(_instantSpeed)}\nСредняя: ${unit.formatSpeed(avgSpeed)}\nМаксимальная: ${unit.formatSpeed(_maxSpeed)}\n\nПоследний пакет (№$_notifyPacketCount, ${_lastPacketData.length} байт):\n$hexData$decodedImuText";
  }

  void _decodeImuPacket(List<int> data, {required bool writeCsv}) {
    final packet = DpImuPacket.fromBytes(data, config: imuConfig);
    if (packet == null) {
      _invalidImuPacketCount++;
      _lastInvalidImuPacketLength = data.length;
      return;
    }

    _lastImuPacket = packet;
    _decodedImuPacketCount++;
    if (writeCsv) {
      csvManager.writeImuToCsv(packet);
    }
  }

  @override
  void dispose() {
    csvManager.dispose();
    _connectionSub?.cancel();
    _notifySub?.cancel();
    _notifyUpdateTimer?.cancel();
    _testDurationTimer?.cancel();
    logTextNotifier.dispose();
    isTestingNotifier.dispose();
    telemetryNotifier.dispose();
    disconnect();
    super.dispose();
  }
}

class _ImuRangeAutoTestStep {
  final String title;
  final String filenameLabel;
  final ImuSensorConfig config;

  const _ImuRangeAutoTestStep({
    required this.title,
    required this.filenameLabel,
    required this.config,
  });
}
