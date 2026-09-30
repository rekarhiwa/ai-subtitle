enum ExportQuality {
  fast,
  balanced,
  high,
}

extension ExportQualityX on ExportQuality {
  String get label => switch (this) {
        ExportQuality.fast => 'Fast',
        ExportQuality.balanced => 'Balanced',
        ExportQuality.high => 'High Quality',
      };

  /// libx264 CRF — lower is higher quality.
  int get crf => switch (this) {
        ExportQuality.fast => 28,
        ExportQuality.balanced => 23,
        ExportQuality.high => 18,
      };

  String get preset => switch (this) {
        ExportQuality.fast => 'veryfast',
        ExportQuality.balanced => 'medium',
        ExportQuality.high => 'slow',
      };
}
