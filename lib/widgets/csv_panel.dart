// ==> lib/widgets/csv_panel.dart <==
import 'package:flutter/material.dart';

import '../controllers/csv_manager.dart';
import '../models/imu_csv_format.dart';

class CsvRecordingPanel extends StatelessWidget {
  final CsvManager csvManager;
  final VoidCallback onFormatChanged;

  const CsvRecordingPanel({
    super.key,
    required this.csvManager,
    required this.onFormatChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Сбор телеметрии (CSV)",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Кнопка выбора папки
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_open),
            label: Text(
              csvManager.saveDirectory == null
                  ? "Выбрать папку для сохранения"
                  : ".../${csvManager.saveDirectory!.split('/').last}",
            ),
            onPressed: () => csvManager.pickSaveDirectory(),
          ),
          const SizedBox(height: 12),

          // Выбор формата
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Формат данных:"),
              ValueListenableBuilder<bool>(
                valueListenable: csvManager.isRecordingCsvNotifier,
                builder: (context, isRecording, child) {
                  return DropdownButton<ImuCsvFormat>(
                    value: csvManager.selectedCsvFormat,
                    onChanged: isRecording
                        ? null
                        : (v) {
                            if (v != null) {
                              csvManager.selectedCsvFormat = v;
                              onFormatChanged(); // Обновление UI снаружи
                            }
                          },
                    items: ImuCsvFormat.values
                        .map(
                          (format) => DropdownMenuItem(
                            value: format,
                            child: Text(format.label),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Управление записью
          ValueListenableBuilder<bool>(
            valueListenable: csvManager.isRecordingCsvNotifier,
            builder: (context, isRecording, child) {
              return Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRecording
                            ? Colors.red
                            : Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: Icon(
                        isRecording ? Icons.stop : Icons.fiber_manual_record,
                      ),
                      label: Text(
                        isRecording ? "Остановить запись" : "Начать запись",
                      ),
                      onPressed: csvManager.saveDirectory == null
                          ? null
                          : () => csvManager.toggleCsvRecording(),
                    ),
                  ),
                  if (isRecording) ...[
                    const SizedBox(width: 16),
                    ValueListenableBuilder<int>(
                      valueListenable: csvManager.recordedLinesNotifier,
                      builder: (context, lines, child) {
                        return Text(
                          "Строк:\n$lines",
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
