import 'dart:typed_data';

import 'package:ble_throughput/models/imu_packet.dart';
import 'package:ble_throughput/models/imu_sensor_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses all snapshots from notify payload', () {
    final payload = ByteData(
      DpImuPacket.timestampSize + (DpImuPacket.snapshotSize * 2),
    );
    payload.setUint64(0, 123456, Endian.little);

    var offset = DpImuPacket.timestampSize;
    for (var snapshot = 0; snapshot < 2; snapshot++) {
      for (var imu = 0; imu < DpImuPacket.sensorCount; imu++) {
        for (var axis = 0; axis < DpImuPacket.axesPerVector; axis++) {
          payload.setInt16(offset, 1000 + snapshot, Endian.little);
          offset += DpImuPacket.bytesPerInt16;
        }
        for (var axis = 0; axis < DpImuPacket.axesPerVector; axis++) {
          payload.setInt16(offset, 2000 + snapshot, Endian.little);
          offset += DpImuPacket.bytesPerInt16;
        }
      }
    }

    final packets = DpImuPacket.packetsFromBytes(payload.buffer.asUint8List());

    expect(packets, hasLength(2));
    expect(packets[0].timestamp, 123456);
    expect(packets[0].snapshotIndex, 0);
    expect(packets[0].imu[0].rawAcc, [1000, 1000, 1000]);
    expect(packets[0].imu[0].rawGyro, [2000, 2000, 2000]);
    expect(packets[1].timestamp, 123456);
    expect(packets[1].snapshotIndex, 1);
    expect(packets[1].imu[0].rawAcc, [1001, 1001, 1001]);
    expect(packets[1].imu[0].rawGyro, [2001, 2001, 2001]);
    expect(DpImuPacket.snapshotCountFromBytes(payload.buffer.asUint8List()), 2);
  });

  test('fromBytes keeps returning the first snapshot for compatibility', () {
    final payload = ByteData(
      DpImuPacket.timestampSize + (DpImuPacket.snapshotSize * 2),
    );
    payload.setUint64(0, 123456, Endian.little);

    var offset = DpImuPacket.timestampSize;
    for (var snapshot = 0; snapshot < 2; snapshot++) {
      for (var imu = 0; imu < DpImuPacket.sensorCount; imu++) {
        for (var axis = 0; axis < DpImuPacket.axesPerVector; axis++) {
          payload.setInt16(offset, 1000 + snapshot, Endian.little);
          offset += DpImuPacket.bytesPerInt16;
        }
        for (var axis = 0; axis < DpImuPacket.axesPerVector; axis++) {
          payload.setInt16(offset, 2000 + snapshot, Endian.little);
          offset += DpImuPacket.bytesPerInt16;
        }
      }
    }

    final packet = DpImuPacket.fromBytes(payload.buffer.asUint8List());

    expect(packet, isNotNull);
    expect(packet!.timestamp, 123456);
    expect(packet.snapshotIndex, 0);
    expect(packet.imu[0].rawAcc, [1000, 1000, 1000]);
    expect(packet.imu[0].rawGyro, [2000, 2000, 2000]);
  });

  test('uses active imu ranges for SI conversion', () {
    final payload = ByteData(DpImuPacket.minPacketSize);
    payload.setUint64(0, 123456, Endian.little);

    var offset = DpImuPacket.timestampSize;
    for (var imu = 0; imu < DpImuPacket.sensorCount; imu++) {
      for (var axis = 0; axis < DpImuPacket.axesPerVector; axis++) {
        payload.setInt16(offset, 1000, Endian.little);
        offset += DpImuPacket.bytesPerInt16;
      }
      for (var axis = 0; axis < DpImuPacket.axesPerVector; axis++) {
        payload.setInt16(offset, 1000, Endian.little);
        offset += DpImuPacket.bytesPerInt16;
      }
    }

    final packet = DpImuPacket.fromBytes(
      payload.buffer.asUint8List(),
      config: const ImuSensorConfig(
        accelOdrHz: 120,
        accelRangeG: 16,
        gyroOdrHz: 120,
        gyroRangeDps: 2000,
      ),
    );

    expect(packet, isNotNull);
    expect(packet!.imu[0].accG[0], closeTo(0.488, 1e-9));
    expect(packet.imu[0].accMs2[0], closeTo(0.488 * 9.80665, 1e-9));
    expect(packet.imu[0].gyroDps[0], closeTo(70.0, 1e-9));
    expect(
      packet.imu[0].gyroRads[0],
      closeTo(70.0 * 3.141592653589793 / 180.0, 1e-9),
    );
  });

  test('rejects payloads shorter than one snapshot', () {
    final invalid = Uint8List(DpImuPacket.minPacketSize - 1);

    expect(DpImuPacket.fromBytes(invalid), isNull);
    expect(DpImuPacket.packetsFromBytes(invalid), isEmpty);
  });

  test('rejects payloads with incomplete trailing snapshot', () {
    final invalid = Uint8List(DpImuPacket.minPacketSize + 1);

    expect(DpImuPacket.fromBytes(invalid), isNull);
    expect(DpImuPacket.packetsFromBytes(invalid), isEmpty);
    expect(DpImuPacket.snapshotCountFromBytes(invalid), 0);
  });
}
