import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class ScanResultTile extends StatelessWidget {
  final ScanResult result;
  final VoidCallback onTap;

  const ScanResultTile({super.key, required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final device = result.device;
    return ListTile(
      title: Text(device.platformName.isNotEmpty ? device.platformName : 'Unknown Device'),
      subtitle: Text(device.remoteId.toString()),
      trailing: Text("${result.rssi} dBm"),
      leading: const Icon(Icons.bluetooth),
      onTap: onTap,
    );
  }
}
