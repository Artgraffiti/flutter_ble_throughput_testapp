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
  final int? rawTemp;
  final double? tempCelsius;

  DpImuData({
    required this.rawAcc,
    required this.rawGyro,
    required this.accMs2,
    required this.gyroRads,
    required this.accG,
    required this.gyroDps,
    this.rawTemp,
    this.tempCelsius,
  });

  bool get hasTemperature => rawTemp != null;

  DpImuData copyWithTemperature({
    required int? rawTemp,
    required double? tempCelsius,
  }) {
    return DpImuData(
      rawAcc: rawAcc,
      rawGyro: rawGyro,
      accMs2: accMs2,
      gyroRads: gyroRads,
      accG: accG,
      gyroDps: gyroDps,
      rawTemp: rawTemp,
      tempCelsius: tempCelsius,
    );
  }

  double get accMagnitudeMs2 => _magnitude(accMs2);

  double get gyroMagnitudeRads => _magnitude(gyroRads);

  static double _magnitude(List<double> values) {
    return sqrt(values.fold<double>(0, (sum, value) => sum + value * value));
  }
}

class DpImuPacket {
  static const int packetVersion = 1;
  static const int packetFlagTemp = 0x01;
  static const int headerSize = 4;
  static const int timestampSize = 8;
  static const int sensorCount = 4;
  static const int axesPerVector = 3;
  static const int bytesPerInt16 = 2;
  static const int bytesPerSensor =
      axesPerVector * bytesPerInt16 * 2; // ACC + GYRO
  static const int snapshotSize = sensorCount * bytesPerSensor;
  static const int tempBlockSize = sensorCount * bytesPerInt16;
  static const int minPacketSize = timestampSize + snapshotSize;
  static const int minLegacyPacketSize = timestampSize + snapshotSize;
  static const int minVersionedPacketSize =
      headerSize + timestampSize + snapshotSize;

  final int timestamp;
  final int snapshotIndex;
  final List<DpImuData> imu;
  final ImuSensorConfig config;
  final int flags;

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
    this.flags = 0,
    this.config = ImuSensorConfig.defaults,
  });

  bool get hasTemperature => (flags & packetFlagTemp) != 0;

  static DpImuPacket? fromBytes(
    List<int> bytes, {
    ImuSensorConfig config = ImuSensorConfig.defaults,
  }) {
    final packets = packetsFromBytes(bytes, config: config);
    if (packets.isEmpty) return null;
    return packets.first;
  }

  static int snapshotCountFromBytes(List<int> bytes) {
    if (_isVersionedPacket(bytes)) {
      final bytesView = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      final byteData = ByteData.sublistView(bytesView);
      return byteData.getUint16(2, Endian.little);
    }

    if (bytes.length < minLegacyPacketSize) return 0;
    final payloadSize = bytes.length - timestampSize;
    if (payloadSize % snapshotSize != 0) return 0;

    return payloadSize ~/ snapshotSize;
  }

  DpImuPacket withFallbackTemperatures(DpImuPacket? fallback) {
    if (hasTemperature ||
        fallback == null ||
        fallback.imu.length != imu.length) {
      return this;
    }

    final mergedImu = <DpImuData>[];
    for (var i = 0; i < imu.length; i++) {
      mergedImu.add(
        imu[i].copyWithTemperature(
          rawTemp: fallback.imu[i].rawTemp,
          tempCelsius: fallback.imu[i].tempCelsius,
        ),
      );
    }

    return DpImuPacket(
      timestamp: timestamp,
      snapshotIndex: snapshotIndex,
      imu: mergedImu,
      config: config,
      flags: fallback.flags,
    );
  }

  static List<DpImuPacket> packetsFromBytes(
    List<int> bytes, {
    ImuSensorConfig config = ImuSensorConfig.defaults,
  }) {
    if (_isVersionedPacket(bytes)) {
      return _packetsFromVersionedBytes(bytes, config: config);
    }

    return _packetsFromLegacyBytes(bytes, config: config);
  }

  static bool _isVersionedPacket(List<int> bytes) {
    if (bytes.length < minVersionedPacketSize || bytes.first != packetVersion) {
      return false;
    }

    final bytesView = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final byteData = ByteData.sublistView(bytesView);
    final flags = byteData.getUint8(1);
    if ((flags & ~packetFlagTemp) != 0) {
      return false;
    }

    final snapshotCount = byteData.getUint16(2, Endian.little);
    if (snapshotCount == 0) {
      return false;
    }

    final expectedLength =
        headerSize +
        timestampSize +
        (snapshotCount * snapshotSize) +
        ((flags & packetFlagTemp) != 0 ? tempBlockSize : 0);

    return expectedLength == bytes.length;
  }

  static List<DpImuPacket> _packetsFromLegacyBytes(
    List<int> bytes, {
    required ImuSensorConfig config,
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
          flags: 0,
          config: config,
        ),
      );
    }

    return packets;
  }

  static List<DpImuPacket> _packetsFromVersionedBytes(
    List<int> bytes, {
    required ImuSensorConfig config,
  }) {
    final bytesView = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final byteData = ByteData.sublistView(bytesView);
    final flags = byteData.getUint8(1);
    final snapshotCount = byteData.getUint16(2, Endian.little);
    final timestamp = byteData.getUint64(headerSize, Endian.little);
    final accelSensitivity =
        _accelSensitivityByRangeG[config.accelRangeG] ??
        _accelSensitivityByRangeG[ImuSensorConfig.defaults.accelRangeG]!;
    final gyroSensitivity =
        _gyroSensitivityByRangeDps[config.gyroRangeDps] ??
        _gyroSensitivityByRangeDps[ImuSensorConfig.defaults.gyroRangeDps]!;
    final rawTemps = (flags & packetFlagTemp) != 0
        ? List<int>.generate(
            sensorCount,
            (index) => byteData.getInt16(
              headerSize +
                  timestampSize +
                  (snapshotCount * snapshotSize) +
                  (index * bytesPerInt16),
              Endian.little,
            ),
          )
        : null;

    int offset = headerSize + timestampSize;
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
        final rawTemp = rawTemps?[i];

        imuList.add(
          DpImuData(
            rawAcc: rawAcc,
            rawGyro: rawGyro,
            accG: accG,
            accMs2: accMs2,
            gyroDps: gyroDps,
            gyroRads: gyroRads,
            rawTemp: rawTemp,
            tempCelsius: rawTemp == null ? null : _tempCelsiusFromRaw(rawTemp),
          ),
        );
      }

      packets.add(
        DpImuPacket(
          timestamp: timestamp,
          snapshotIndex: snapshotIndex,
          imu: imuList,
          flags: flags,
          config: config,
        ),
      );
    }

    return packets;
  }

  static double _tempCelsiusFromRaw(int rawTemp) {
    return (rawTemp / 256.0) + 25.0;
  }
}
