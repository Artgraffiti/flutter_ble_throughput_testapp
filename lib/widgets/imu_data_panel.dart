import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../models/imu_packet.dart';

enum ImuDisplayMode { converted, raw }

class ImuDataPanel extends StatefulWidget {
  final DeviceController controller;

  const ImuDataPanel({super.key, required this.controller});

  @override
  State<ImuDataPanel> createState() => _ImuDataPanelState();
}

class _ImuDataPanelState extends State<ImuDataPanel> {
  ImuDisplayMode _mode = ImuDisplayMode.converted;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.controller.telemetryNotifier,
      builder: (context, value, child) {
        final packet = widget.controller.lastImuPacket;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),
                const SizedBox(height: 12),
                if (packet == null)
                  _buildEmptyState(context)
                else
                  _buildGrid(packet),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sensors_outlined, color: colors.primary),
            const SizedBox(width: 8),
            const Text(
              'IMU данные',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        _StatChip(
          icon: Icons.multiline_chart,
          label: 'Snapshot/s',
          value:
              '${widget.controller.instantSnapshotRate.toStringAsFixed(1)} / '
              '${widget.controller.averageSnapshotRate.toStringAsFixed(1)} / '
              '${widget.controller.maxSnapshotRate.toStringAsFixed(1)}',
          tooltip: 'Мгновенная / средняя / максимальная скорость IMU snapshot',
        ),
        SegmentedButton<ImuDisplayMode>(
          segments: const [
            ButtonSegment(
              value: ImuDisplayMode.converted,
              icon: Icon(Icons.speed_outlined),
              label: Text('SI'),
            ),
            ButtonSegment(
              value: ImuDisplayMode.raw,
              icon: Icon(Icons.tag_outlined),
              label: Text('Raw'),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (selection) {
            setState(() => _mode = selection.first);
          },
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.sensors_off_outlined, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Запустите Notify Test, чтобы увидеть последние значения с 4 IMU.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(DpImuPacket packet) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 4
            : constraints.maxWidth >= 620
            ? 2
            : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: packet.imu.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 252,
          ),
          itemBuilder: (context, index) {
            return _ImuSensorCard(
              index: index,
              data: packet.imu[index],
              mode: _mode,
            );
          },
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String tooltip;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colors.primary),
            const SizedBox(width: 8),
            Text(
              '$label: $value',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImuSensorCard extends StatelessWidget {
  final int index;
  final DpImuData data;
  final ImuDisplayMode mode;

  const _ImuSensorCard({
    required this.index,
    required this.data,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final converted = mode == ImuDisplayMode.converted;

    final accValues = converted
        ? data.accMs2.map((value) => value.toStringAsFixed(2)).toList()
        : data.rawAcc.map((value) => value.toString()).toList();
    final gyroValues = converted
        ? data.gyroRads.map((value) => value.toStringAsFixed(2)).toList()
        : data.rawGyro.map((value) => value.toString()).toList();
    final tempValue = data.rawTemp == null
        ? '--'
        : converted
        ? '${data.tempCelsius!.toStringAsFixed(2)} C'
        : data.rawTemp!.toString();

    final accMagnitude = converted
        ? data.accMagnitudeMs2
        : _rawMagnitude(data.rawAcc);
    final gyroMagnitude = converted
        ? data.gyroMagnitudeRads
        : _rawMagnitude(data.rawGyro);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$index',
                  style: TextStyle(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'IMU',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                converted ? 'SI' : 'RAW',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _VectorSection(
            title: converted ? 'ACC  m/s2' : 'ACC raw',
            values: accValues,
            magnitude: accMagnitude,
            scale: converted ? 20.0 : 32768.0,
            color: colors.primary,
          ),
          const SizedBox(height: 8),
          _VectorSection(
            title: converted ? 'GYRO rad/s' : 'GYRO raw',
            values: gyroValues,
            magnitude: gyroMagnitude,
            scale: converted ? 70.0 : 32768.0,
            color: colors.tertiary,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colors.secondaryContainer.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              converted ? 'TEMP $tempValue' : 'TEMP raw $tempValue',
              style: TextStyle(
                color: colors.onSecondaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static double _rawMagnitude(List<int> values) {
    return math.sqrt(
      values.fold<double>(0, (sum, value) => sum + value * value),
    );
  }
}

class _VectorSection extends StatelessWidget {
  final String title;
  final List<String> values;
  final double magnitude;
  final double scale;
  final Color color;

  const _VectorSection({
    required this.title,
    required this.values,
    required this.magnitude,
    required this.scale,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final progress = (magnitude / scale).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '|v| ${magnitude.toStringAsFixed(magnitude >= 100 ? 0 : 2)}',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < values.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _AxisValue(axis: 'XYZ'[i], value: values[i]),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _AxisValue extends StatelessWidget {
  final String axis;
  final String value;

  const _AxisValue({required this.axis, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          axis,
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontFeatures: [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
