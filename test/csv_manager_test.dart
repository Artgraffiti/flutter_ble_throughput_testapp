import 'dart:io';

import 'package:ble_throughput/controllers/csv_manager.dart';
import 'package:ble_throughput/models/imu_csv_format.dart';
import 'package:ble_throughput/models/imu_packet.dart';
import 'package:ble_throughput/models/imu_sensor_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('writes imu index column in converted csv', () async {
    final tempDir = await Directory.systemTemp.createTemp('csv_manager_test');
    final logNotifier = ValueNotifier<String>('');
    final manager = CsvManager(logNotifier)
      ..saveDirectory = tempDir.path
      ..selectedCsvFormat = ImuCsvFormat.converted;

    await manager.startCsvRecording();
    manager.writeImuToCsv(_packet());
    await manager.stopCsvRecording();

    final file = tempDir.listSync().whereType<File>().single;
    final lines = await file.readAsLines();

    expect(
      lines.first,
      'timestamp_us,imu_index,acc_x_ms2,acc_y_ms2,acc_z_ms2,gyro_x_rads,gyro_y_rads,gyro_z_rads',
    );
    expect(lines[1].startsWith('123,0,'), isTrue);
    expect(lines[2].startsWith('123,1,'), isTrue);

    manager.dispose();
    logNotifier.dispose();
    await tempDir.delete(recursive: true);
  });

  test('writes imu index column in raw csv', () async {
    final tempDir = await Directory.systemTemp.createTemp('csv_manager_test');
    final logNotifier = ValueNotifier<String>('');
    final manager = CsvManager(logNotifier)
      ..saveDirectory = tempDir.path
      ..selectedCsvFormat = ImuCsvFormat.raw;

    await manager.startCsvRecording();
    manager.writeImuToCsv(_packet());
    await manager.stopCsvRecording();

    final file = tempDir.listSync().whereType<File>().single;
    final lines = await file.readAsLines();

    expect(
      lines.first,
      'timestamp_us,imu_index,acc_x_raw,acc_y_raw,acc_z_raw,gyro_x_raw,gyro_y_raw,gyro_z_raw',
    );
    expect(lines[1].startsWith('123,0,'), isTrue);
    expect(lines[2].startsWith('123,1,'), isTrue);

    manager.dispose();
    logNotifier.dispose();
    await tempDir.delete(recursive: true);
  });

  test('includes imu config in csv filename', () async {
    final tempDir = await Directory.systemTemp.createTemp('csv_manager_test');
    final logNotifier = ValueNotifier<String>('');
    final manager = CsvManager(
      logNotifier,
      imuConfigProvider: () => const ImuSensorConfig(
        accelOdrHz: 120,
        accelRangeG: 16,
        gyroOdrHz: 240,
        gyroRangeDps: 2000,
      ),
    )..saveDirectory = tempDir.path;

    await manager.startCsvRecording();
    await manager.stopCsvRecording();

    final file = tempDir.listSync().whereType<File>().single;

    expect(
      file.uri.pathSegments.last,
      contains('acc120hz_16g_gyro240hz_2000dps'),
    );

    manager.dispose();
    logNotifier.dispose();
    await tempDir.delete(recursive: true);
  });
}

DpImuPacket _packet() {
  return DpImuPacket(timestamp: 123, snapshotIndex: 0, imu: [_imu(1), _imu(2)]);
}

DpImuData _imu(int seed) {
  return DpImuData(
    rawAcc: [seed, seed + 1, seed + 2],
    rawGyro: [seed + 3, seed + 4, seed + 5],
    accMs2: [seed * 1.0, seed + 1.0, seed + 2.0],
    gyroRads: [seed + 3.0, seed + 4.0, seed + 5.0],
    accG: [seed * 0.1, seed * 0.2, seed * 0.3],
    gyroDps: [seed * 10.0, seed * 20.0, seed * 30.0],
  );
}
