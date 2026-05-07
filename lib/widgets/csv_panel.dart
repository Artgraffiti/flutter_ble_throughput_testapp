import 'package:flutter/material.dart';
import '../controllers/csv_manager.dart';
import '../models/imu_csv_format.dart';

class CsvRecordingPanel extends StatelessWidget {
  final CsvManager csvManager;
  final VoidCallback onFormatChanged; 

  const CsvRecordingPanel({super.key, required this.csvManager, required this.onFormatChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("Сбор телеметрии (CSV)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_open),
            label: Text(csvManager.saveDirectory == null ? "Выбрать папку для сохранения" : ".../${csvManager.saveDirectory!.split('/').last}"), 
            onPressed: () => csvManager.pickSaveDirectory(),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Формат данных:"),
              ValueListenableBuilder<bool>(
                valueListenable: csvManager.isRecordingCsvNotifier,
                builder: (context, isRecording, child) => DropdownButton<ImuCsvFormat>(
                  value: csvManager.selectedCsvFormat,
                  onChanged: isRecording ? null : (v) {
                    if (v != null) {
                      csvManager.selectedCsvFormat = v;
                      onFormatChanged(); // Перерисовка UI для обновления значения dropdown
                    }
                  },
                  items: ImuCsvFormat.values.map((f) => DropdownMenuItem(value: f, child: Text(f.label))).toList(),
                )
              ),
            ],
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<bool>(
            valueListenable: csvManager.isRecordingCsvNotifier,
            builder: (context, isRecording, child) => Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: isRecording ? Colors.red : Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                    icon: Icon(isRecording ? Icons.stop : Icons.fiber_manual_record),
                    label: Text(isRecording ? "Остановить запись" : "Начать запись"),
                    onPressed: csvManager.saveDirectory == null ? null : () => csvManager.toggleCsvRecording(),
                  ),
                ),
                if (isRecording) ...[
                  const SizedBox(width: 16),
                  ValueListenableBuilder<int>(
                    valueListenable: csvManager.recordedLinesNotifier,
                    builder: (context, lines, child) => Text("Строк:\n$lines", textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ]
              ],
            )
          ),
        ],
      ),
    );
  }
}