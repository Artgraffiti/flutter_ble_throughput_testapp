import 'dart:typed_data';
import 'dart:math';

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

  // Коэффициенты пересчета сырых данных IMU-сенсора
  // Акселерометр: +-8g -> 0.244 mg/LSB
  static const double _accelSensitivity = 0.244 / 1000.0; // g/LSB
  static const double _gravity = 9.80665; // м/с^2

  // Гироскоп: +-4000 dps -> 140 mdps/LSB
  static const double _gyroSensitivity = 140.0 / 1000.0; // dps/LSB

  DpImuPacket({
    required this.timestamp,
    required this.snapshotIndex,
    required this.imu,
  });

  static DpImuPacket? fromBytes(List<int> bytes) {
    if (bytes.length < minPacketSize) return null;

    final bytesView = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final byteData = ByteData.sublistView(bytesView);

    final timestamp = byteData.getUint64(0, Endian.little);
    int offset = timestampSize;
    final imuList = <DpImuData>[];

    for (int i = 0; i < sensorCount; i++) {
      List<int> rawAcc = [
        byteData.getInt16(offset, Endian.little),
        byteData.getInt16(offset + 2, Endian.little),
        byteData.getInt16(offset + 4, Endian.little),
      ];
      offset += 6;

      List<int> rawGyro = [
        byteData.getInt16(offset, Endian.little),
        byteData.getInt16(offset + 2, Endian.little),
        byteData.getInt16(offset + 4, Endian.little),
      ];
      offset += 6;

      List<double> accG = rawAcc.map((val) => val * _accelSensitivity).toList();
      List<double> accMs2 = accG.map((val) => val * _gravity).toList();

      List<double> gyroDps = rawGyro
          .map((val) => val * _gyroSensitivity)
          .toList();
      List<double> gyroRads = gyroDps.map((val) => val * (pi / 180.0)).toList();

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

    return DpImuPacket(timestamp: timestamp, snapshotIndex: 0, imu: imuList);
  }
}
