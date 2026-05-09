import 'dart:typed_data';

class ImuSensorConfig {
  final int accelOdrHz;
  final int accelRangeG;
  final int gyroOdrHz;
  final int gyroRangeDps;

  const ImuSensorConfig({
    required this.accelOdrHz,
    required this.accelRangeG,
    required this.gyroOdrHz,
    required this.gyroRangeDps,
  });

  static const defaults = ImuSensorConfig(
    accelOdrHz: 3840,
    accelRangeG: 8,
    gyroOdrHz: 3840,
    gyroRangeDps: 4000,
  );

  static const odrOptions = <int>[
    15,
    30,
    60,
    120,
    240,
    480,
    960,
    1920,
    3840,
    7680,
  ];
  static const accelRangeOptions = <int>[4, 8, 16, 32];
  static const gyroRangeOptions = <int>[125, 250, 500, 1000, 2000, 4000];

  ImuSensorConfig copyWith({
    int? accelOdrHz,
    int? accelRangeG,
    int? gyroOdrHz,
    int? gyroRangeDps,
  }) {
    return ImuSensorConfig(
      accelOdrHz: accelOdrHz ?? this.accelOdrHz,
      accelRangeG: accelRangeG ?? this.accelRangeG,
      gyroOdrHz: gyroOdrHz ?? this.gyroOdrHz,
      gyroRangeDps: gyroRangeDps ?? this.gyroRangeDps,
    );
  }

  Uint8List toBytes() {
    final data = ByteData(8);
    data.setUint16(0, accelOdrHz, Endian.little);
    data.setUint16(2, accelRangeG, Endian.little);
    data.setUint16(4, gyroOdrHz, Endian.little);
    data.setUint16(6, gyroRangeDps, Endian.little);
    return data.buffer.asUint8List();
  }

  static ImuSensorConfig fromBytes(List<int> bytes) {
    if (bytes.length < 8) {
      throw ArgumentError('IMU config packet must contain 8 bytes');
    }

    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    return ImuSensorConfig(
      accelOdrHz: data.getUint16(0, Endian.little),
      accelRangeG: data.getUint16(2, Endian.little),
      gyroOdrHz: data.getUint16(4, Endian.little),
      gyroRangeDps: data.getUint16(6, Endian.little),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ImuSensorConfig &&
        other.accelOdrHz == accelOdrHz &&
        other.accelRangeG == accelRangeG &&
        other.gyroOdrHz == gyroOdrHz &&
        other.gyroRangeDps == gyroRangeDps;
  }

  @override
  int get hashCode =>
      Object.hash(accelOdrHz, accelRangeG, gyroOdrHz, gyroRangeDps);
}
