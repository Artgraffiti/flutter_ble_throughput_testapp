import 'dart:typed_data';

import 'package:ble_throughput/models/imu_packet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses first snapshot from notify payload like legacy decoder', () {
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

  test('rejects payloads shorter than one snapshot', () {
    final invalid = Uint8List(DpImuPacket.minPacketSize - 1);

    expect(DpImuPacket.fromBytes(invalid), isNull);
  });
}
