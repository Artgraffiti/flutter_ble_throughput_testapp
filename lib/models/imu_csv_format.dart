enum ImuCsvFormat {
  raw('Сырые данные (LSB)'),
  converted('СИ (м/с^2 и рад/с)');

  final String label;
  const ImuCsvFormat(this.label);
}