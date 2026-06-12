// ==> lib/controllers/csv_manager.dart <==
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/imu_packet.dart';
import '../models/imu_csv_format.dart';
import '../models/imu_sensor_config.dart';

class CsvManager {
  static const int _flushPacketThreshold = 1024;
  static const int _recordedLinesUiUpdateThreshold = 500;

  final ValueNotifier<String> logNotifier;
  final ImuSensorConfig Function()? imuConfigProvider;

  String? saveDirectory;
  ImuCsvFormat selectedCsvFormat = ImuCsvFormat.converted;

  final ValueNotifier<bool> isRecordingCsvNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> recordedLinesNotifier = ValueNotifier<int>(0);

  Isolate? _writerIsolate;
  SendPort? _writerSendPort;
  int _recordedLinesCount = 0;
  final StringBuffer _pendingCsvRows = StringBuffer();

  CsvManager(this.logNotifier, {this.imuConfigProvider});

  bool get isRecording => isRecordingCsvNotifier.value;

  Future<void> pickSaveDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Выберите папку для сохранения логов',
    );
    if (selectedDirectory != null) {
      saveDirectory = selectedDirectory;
      // Принудительное обновление UI
      isRecordingCsvNotifier.value = isRecordingCsvNotifier.value;
    }
  }

  Future<void> toggleCsvRecording() async {
    if (isRecordingCsvNotifier.value) {
      await stopCsvRecording();
    } else {
      await startCsvRecording();
    }
  }

  Future<bool> startCsvRecording({
    ImuSensorConfig? config,
    String? label,
  }) async {
    if (saveDirectory == null) {
      logNotifier.value = "Ошибка: Не выбрана папка для сохранения.";
      return false;
    }

    try {
      String timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final activeConfig = config ?? imuConfigProvider?.call();
      final filenameParts = [
        'telemetry',
        timestamp,
        if (activeConfig != null) _formatImuConfigForFilename(activeConfig),
        if (label != null && label.isNotEmpty) _sanitizeFilenamePart(label),
      ];
      String filename = '${filenameParts.join('_')}.csv';
      File file = File('$saveDirectory/$filename');

      await _startWriterIsolate(
        file.path,
        _csvHeaderForFormat(selectedCsvFormat),
      );

      _recordedLinesCount = 0;
      recordedLinesNotifier.value = 0;
      isRecordingCsvNotifier.value = true;
      logNotifier.value = "Начата запись в файл: $filename";
      return true;
    } catch (e) {
      logNotifier.value = "Ошибка создания файла: $e";
      return false;
    }
  }

  Future<void> stopCsvRecording() async {
    if (!isRecordingCsvNotifier.value) return;

    try {
      _flushPendingRows();
      await _stopWriterIsolate();
      recordedLinesNotifier.value = _recordedLinesCount;
      isRecordingCsvNotifier.value = false;
      logNotifier.value =
          "Запись остановлена. Сохранено строк: $_recordedLinesCount";
    } catch (e) {
      logNotifier.value = "Ошибка при закрытии файла: $e";
    }
  }

  void writeImuToCsv(DpImuPacket packet) {
    writeImuPacketsToCsv([packet]);
  }

  void writeImuPacketsToCsv(List<DpImuPacket> packets) {
    if (_writerSendPort == null || !isRecording) return;

    for (final packet in packets) {
      _recordedLinesCount += packet.imu.length;
    }

    _pendingCsvRows.write(_buildCsvRows(packets, selectedCsvFormat));

    if (_recordedLinesCount % _flushPacketThreshold == 0) {
      _flushPendingRows();
    }

    // Обновляем UI счётчика реже, чтобы не нагружать main isolate.
    if (_recordedLinesCount % _recordedLinesUiUpdateThreshold == 0) {
      recordedLinesNotifier.value = _recordedLinesCount;
    }
  }

  void enqueueNotifyDataForCsv(List<int> data, ImuSensorConfig config) {
    if (_writerSendPort == null || !isRecording) return;

    final snapshotCount = DpImuPacket.snapshotCountFromBytes(data);
    if (snapshotCount == 0) return;

    _recordedLinesCount += snapshotCount * DpImuPacket.sensorCount;
    _maybeUpdateRecordedLinesUi();

    _writerSendPort!.send({
      'type': 'notify',
      'data': Uint8List.fromList(data),
      'format': selectedCsvFormat.index,
      'config': [
        config.accelOdrHz,
        config.accelRangeG,
        config.gyroOdrHz,
        config.gyroRangeDps,
      ],
    });
  }

  void _flushPendingRows() {
    if (_pendingCsvRows.isEmpty || _writerSendPort == null) return;

    _writerSendPort!.send({'type': 'rows', 'rows': _pendingCsvRows.toString()});
    _pendingCsvRows.clear();
  }

  void _maybeUpdateRecordedLinesUi() {
    if (_recordedLinesCount % _recordedLinesUiUpdateThreshold == 0) {
      recordedLinesNotifier.value = _recordedLinesCount;
    }
  }

  Future<void> _startWriterIsolate(String filePath, String header) async {
    final receivePort = ReceivePort();
    _writerIsolate = await Isolate.spawn(
      _csvWriterIsolateMain,
      receivePort.sendPort,
    );

    final sendPortCompleter = Completer<SendPort>();
    late final StreamSubscription<dynamic> subscription;
    subscription = receivePort.listen((message) {
      if (!sendPortCompleter.isCompleted && message is SendPort) {
        sendPortCompleter.complete(message);
      }
    });

    final sendPort = await sendPortCompleter.future;
    final ackPort = ReceivePort();
    sendPort.send({
      'type': 'init',
      'path': filePath,
      'header': header,
      'replyTo': ackPort.sendPort,
    });

    final ack = await ackPort.first as Map<dynamic, dynamic>;
    await subscription.cancel();
    receivePort.close();
    ackPort.close();

    if (ack['ok'] != true) {
      _writerIsolate?.kill(priority: Isolate.immediate);
      _writerIsolate = null;
      _writerSendPort = null;
      throw StateError('CSV writer init failed: ${ack['error']}');
    }

    _writerSendPort = sendPort;
  }

  Future<void> _stopWriterIsolate() async {
    final sendPort = _writerSendPort;
    if (sendPort == null) return;

    final ackPort = ReceivePort();
    sendPort.send({'type': 'close', 'replyTo': ackPort.sendPort});

    await ackPort.first;
    ackPort.close();
    _writerSendPort = null;
    _writerIsolate = null;
  }

  static String _formatImuConfigForFilename(ImuSensorConfig config) {
    return [
      'acc${config.accelOdrHz}hz',
      '${config.accelRangeG}g',
      'gyro${config.gyroOdrHz}hz',
      '${config.gyroRangeDps}dps',
    ].join('_');
  }

  static String _sanitizeFilenamePart(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9а-яё]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  void dispose() {
    stopCsvRecording();
    isRecordingCsvNotifier.dispose();
    recordedLinesNotifier.dispose();
  }
}

String _csvHeaderForFormat(ImuCsvFormat format) {
  return format == ImuCsvFormat.raw
      ? 'timestamp_us,imu_index,acc_x_raw,acc_y_raw,acc_z_raw,gyro_x_raw,gyro_y_raw,gyro_z_raw'
      : 'timestamp_us,imu_index,acc_x_ms2,acc_y_ms2,acc_z_ms2,gyro_x_rads,gyro_y_rads,gyro_z_rads';
}

String _buildCsvRows(List<DpImuPacket> packets, ImuCsvFormat format) {
  final rows = StringBuffer();

  for (final packet in packets) {
    for (var imuIndex = 0; imuIndex < packet.imu.length; imuIndex++) {
      final imu = packet.imu[imuIndex];
      if (format == ImuCsvFormat.raw) {
        rows.writeln(
          '${packet.timestamp},$imuIndex,${imu.rawAcc[0]},${imu.rawAcc[1]},${imu.rawAcc[2]},${imu.rawGyro[0]},${imu.rawGyro[1]},${imu.rawGyro[2]}',
        );
      } else {
        rows.writeln(
          '${packet.timestamp},$imuIndex,${imu.accMs2[0]},${imu.accMs2[1]},${imu.accMs2[2]},${imu.gyroRads[0]},${imu.gyroRads[1]},${imu.gyroRads[2]}',
        );
      }
    }
  }

  return rows.toString();
}

Future<void> _csvWriterIsolateMain(SendPort mainSendPort) async {
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);

  IOSink? sink;

  await for (final dynamic message in commandPort) {
    if (message is! Map) {
      continue;
    }

    final type = message['type'];
    if (type == 'init') {
      final replyTo = message['replyTo'] as SendPort;
      try {
        final file = File(message['path'] as String);
        sink = file.openWrite();
        sink.writeln(message['header'] as String);
        replyTo.send({'ok': true});
      } catch (e) {
        replyTo.send({'ok': false, 'error': e.toString()});
      }
      continue;
    }

    if (type == 'rows') {
      if (sink != null) {
        sink.write(message['rows'] as String);
      }
      continue;
    }

    if (type == 'notify') {
      if (sink != null) {
        final data = message['data'] as Uint8List;
        final format = ImuCsvFormat.values[message['format'] as int];
        final configValues = (message['config'] as List).cast<int>();
        final config = ImuSensorConfig(
          accelOdrHz: configValues[0],
          accelRangeG: configValues[1],
          gyroOdrHz: configValues[2],
          gyroRangeDps: configValues[3],
        );
        final packets = DpImuPacket.packetsFromBytes(data, config: config);
        if (packets.isNotEmpty) {
          sink.write(_buildCsvRows(packets, format));
        }
      }
      continue;
    }

    if (type == 'close') {
      final replyTo = message['replyTo'] as SendPort;
      if (sink != null) {
        await sink.flush();
        await sink.close();
      }
      replyTo.send({'ok': true});
      commandPort.close();
      break;
    }
  }
}
