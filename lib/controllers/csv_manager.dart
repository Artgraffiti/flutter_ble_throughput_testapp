import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../models/imu_packet.dart';
import '../models/imu_csv_format.dart';

class CsvManager {
  final ValueNotifier<String> logNotifier; // Ссылка на логгер из DeviceController

  String? saveDirectory;
  ImuCsvFormat selectedCsvFormat = ImuCsvFormat.converted;
  
  final ValueNotifier<bool> isRecordingCsvNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> recordedLinesNotifier = ValueNotifier<int>(0);
  
  IOSink? _csvSink;
  int _recordedLinesCount = 0;

  CsvManager(this.logNotifier);

  Future<void> pickSaveDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Выберите папку для сохранения логов',
    );
    if (selectedDirectory != null) {
      saveDirectory = selectedDirectory;
      // Принудительное обновление слушателей UI (вызовется при перерисовке)
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

  Future<void> startCsvRecording() async {
    if (saveDirectory == null) {
      logNotifier.value = "Ошибка: Не выбрана папка для сохранения.";
      return;
    }

    try {
      String timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      String filename = 'telemetry_$timestamp.csv';
      File file = File('$saveDirectory/$filename');
      
      _csvSink = file.openWrite();
      
      if (selectedCsvFormat == ImuCsvFormat.raw) {
        _csvSink?.writeln("timestamp_us,acc_x_raw,acc_y_raw,acc_z_raw,gyro_x_raw,gyro_y_raw,gyro_z_raw");
      } else {
        _csvSink?.writeln("timestamp_us,acc_x_ms2,acc_y_ms2,acc_z_ms2,gyro_x_rads,gyro_y_rads,gyro_z_rads");
      }

      _recordedLinesCount = 0;
      recordedLinesNotifier.value = 0;
      isRecordingCsvNotifier.value = true;
      logNotifier.value = "Начата запись в файл: $filename";
    } catch (e) {
      logNotifier.value = "Ошибка создания файла: $e";
    }
  }

  Future<void> stopCsvRecording() async {
    if (!isRecordingCsvNotifier.value) return;

    try {
      await _csvSink?.flush();
      await _csvSink?.close();
      _csvSink = null;
      isRecordingCsvNotifier.value = false;
      logNotifier.value = "Запись остановлена. Сохранено строк: $_recordedLinesCount";
    } catch (e) {
      logNotifier.value = "Ошибка при закрытии файла: $e";
    }
  }

  void writeImuToCsv(DpImuPacket packet) {
    if (_csvSink == null || !isRecordingCsvNotifier.value) return;

    for (var imu in packet.imu) {
      if (selectedCsvFormat == ImuCsvFormat.raw) {
        _csvSink?.writeln("${packet.timestamp},${imu.rawAcc[0]},${imu.rawAcc[1]},${imu.rawAcc[2]},${imu.rawGyro[0]},${imu.rawGyro[1]},${imu.rawGyro[2]}");
      } else {
        _csvSink?.writeln("${packet.timestamp},${imu.accMs2[0]},${imu.accMs2[1]},${imu.accMs2[2]},${imu.gyroRads[0]},${imu.gyroRads[1]},${imu.gyroRads[2]}");
      }
      _recordedLinesCount++;
    }

    if (_recordedLinesCount % 50 == 0) {
      recordedLinesNotifier.value = _recordedLinesCount;
    }
  }

  void dispose() {
    stopCsvRecording();
    isRecordingCsvNotifier.dispose();
    recordedLinesNotifier.dispose();
  }
}