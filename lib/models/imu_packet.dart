import 'dart:typed_data';
import 'dart:math';

import 'imu_sensor_config.dart';

class DpImuData {
  final List<int> rawAcc;
  final List<int> rawGyro;
  final List<double> accMs2; // м/с^2
  final List<double> gyroRads; // рад/с
  final List<double> accG; // g
  final List<double> gyroDps; // градусы/с

  DpImuData({
    required this.rawAcc,
    required this.rawGyro,
    required this.accMs2,
    required this.gyroRads,
    required this.accG,
    required this.gyroDps,
  });

  double get accMagnitudeMs2 => _magnitude(accMs2);

  double get gyroMagnitudeRads => _magnitude(gyroRads);

  static double _magnitude(List<double> values) {
    return sqrt(values.fold<double>(0, (sum, value) => sum + value * value));
  }
}

class DpImuPacket {
  static const int timestampSize = 8;
  static const int sensorCount = 4;
  static const int axesPerVector = 3;
  static const int bytesPerInt16 = 2;
  static const int bytesPerSensor =
      axesPerVector * bytesPerInt16 * 2; // ACC + GYRO
  static const int snapshotSize = sensorCount * bytesPerSensor;
  static const int minPacketSize = timestampSize + snapshotSize;

  final int timestamp;
  final int snapshotIndex;
  final List<DpImuData> imu;
  final ImuSensorConfig config;

  static const double _gravity = 9.80665; // м/с^2
  static const Map<int, double> _accelSensitivityByRangeG = {
    4: 0.122 / 1000.0,
    8: 0.244 / 1000.0,
    16: 0.488 / 1000.0,
    32: 0.976 / 1000.0,
  };
  static const Map<int, double> _gyroSensitivityByRangeDps = {
    125: 4.375 / 1000.0,
    250: 8.75 / 1000.0,
    500: 17.5 / 1000.0,
    1000: 35.0 / 1000.0,
    2000: 70.0 / 1000.0,
    4000: 140.0 / 1000.0,
  };

  DpImuPacket({
    required this.timestamp,
    required this.snapshotIndex,
    required this.imu,
    this.config = ImuSensorConfig.defaults,
  });

  static DpImuPacket? fromBytes(
    List<int> bytes, {
    ImuSensorConfig config = ImuSensorConfig.defaults,
  }) {
    final packets = packetsFromBytes(bytes, config: config);
    if (packets.isEmpty) return null;
    return packets.first;
  }

  static int snapshotCountFromBytes(List<int> bytes) {
    if (bytes.length < minPacketSize) return 0;

    final payloadSize = bytes.length - timestampSize;
    if (payloadSize % snapshotSize != 0) return 0;

    return payloadSize ~/ snapshotSize;
  }

  static List<DpImuPacket> packetsFromBytes(
    List<int> bytes, {
    ImuSensorConfig config = ImuSensorConfig.defaults,
  }) {
    final snapshotCount = snapshotCountFromBytes(bytes);
    if (snapshotCount == 0) return const [];
    final bytesView = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final byteData = ByteData.sublistView(bytesView);

    final timestamp = byteData.getUint64(0, Endian.little);
    final accelSensitivity =
        _accelSensitivityByRangeG[config.accelRangeG] ??
        _accelSensitivityByRangeG[ImuSensorConfig.defaults.accelRangeG]!;
    final gyroSensitivity =
        _gyroSensitivityByRangeDps[config.gyroRangeDps] ??
        _gyroSensitivityByRangeDps[ImuSensorConfig.defaults.gyroRangeDps]!;
    int offset = timestampSize;
    final packets = <DpImuPacket>[];

    for (
      int snapshotIndex = 0;
      snapshotIndex < snapshotCount;
      snapshotIndex++
    ) {
      final imuList = <DpImuData>[];

      for (int i = 0; i < sensorCount; i++) {
        final rawAcc = [
          byteData.getInt16(offset, Endian.little),
          byteData.getInt16(offset + 2, Endian.little),
          byteData.getInt16(offset + 4, Endian.little),
        ];
        offset += 6;

        final rawGyro = [
          byteData.getInt16(offset, Endian.little),
          byteData.getInt16(offset + 2, Endian.little),
          byteData.getInt16(offset + 4, Endian.little),
        ];
        offset += 6;

        final accG = rawAcc.map((val) => val * accelSensitivity).toList();
        final accMs2 = accG.map((val) => val * _gravity).toList();

        final gyroDps = rawGyro.map((val) => val * gyroSensitivity).toList();
        final gyroRads = gyroDps.map((val) => val * (pi / 180.0)).toList();

        imuList.add(
          DpImuData(
            rawAcc: rawAcc,
            rawGyro: rawGyro,
            accG: accG,
            accMs2: accMs2,
            gyroDps: gyroDps,
            gyroRads: gyroRads,
          ),
        );
      }

      packets.add(
        DpImuPacket(
          timestamp: timestamp,
          snapshotIndex: snapshotIndex,
          imu: imuList,
          config: config,
        ),
      );
    }

    return packets;
  }
}
