enum ThroughputUnit {
  bits,
  bytes,
  kilobits,
  kilobytes,
  megabits,
  megabytes;

  String formatSpeed(double bytesPerSec) {
    switch (this) {
      case ThroughputUnit.bits:
        return "${(bytesPerSec * 8).toStringAsFixed(0)} бит/с";
      case ThroughputUnit.bytes:
        return "${bytesPerSec.toStringAsFixed(0)} Байт/с";
      case ThroughputUnit.kilobits:
        return "${((bytesPerSec * 8) / 1000).toStringAsFixed(2)} Кбит/с";
      case ThroughputUnit.kilobytes:
        return "${(bytesPerSec / 1024).toStringAsFixed(2)} Кбайт/с";
      case ThroughputUnit.megabits:
        return "${((bytesPerSec * 8) / 1000000).toStringAsFixed(2)} Мбит/с";
      case ThroughputUnit.megabytes:
        return "${(bytesPerSec / (1024 * 1024)).toStringAsFixed(2)} Мбайт/с";
    }
  }
}
