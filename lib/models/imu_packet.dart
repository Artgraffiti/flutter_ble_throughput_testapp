import 'dart:typed_data';
import 'dart:math';

class DpImuData {
  final List<int> rawAcc;
  final List<int> rawGyro;
  final List<double> accMs2;   // м/с^2
  final List<double> gyroRads; // рад/с
  final List<double> accG;     // g
  final List<double> gyroDps;  // градусы/с

  DpImuData({
    required this.rawAcc, 
    required this.rawGyro,
    required this.accMs2,
    required this.gyroRads,
    required this.accG,
    required this.gyroDps,
  });
}

class DpImuPacket {
  final int timestamp; 
  final List<DpImuData> imu; 

  // Коэффициенты пересчета сырых данных IMU-сенсора
  // Акселерометр: +-8g -> 0.244 mg/LSB
  static const double _accelSensitivity = 0.244 / 1000.0; // g/LSB
  static const double _gravity = 9.80665; // м/с^2

  // Гироскоп: +-4000 dps -> 140 mdps/LSB
  static const double _gyroSensitivity = 140.0 / 1000.0; // dps/LSB

  DpImuPacket({required this.timestamp, required this.imu});

  static DpImuPacket? fromBytes(List<int> bytes) {
    if (bytes.length < 56) return null;

    final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
    int offset = 0;

    final timestamp = byteData.getUint64(offset, Endian.little);
    offset += 8;

    List<DpImuData> imuList = [];
    
    for (int i = 0; i < 4; i++) {
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

      List<double> gyroDps = rawGyro.map((val) => val * _gyroSensitivity).toList();
      List<double> gyroRads = gyroDps.map((val) => val * (pi / 180.0)).toList();

      imuList.add(DpImuData(
        rawAcc: rawAcc,
        rawGyro: rawGyro,
        accG: accG,
        accMs2: accMs2,
        gyroDps: gyroDps,
        gyroRads: gyroRads,
      ));
    }

    return DpImuPacket(timestamp: timestamp, imu: imuList);
  }
}