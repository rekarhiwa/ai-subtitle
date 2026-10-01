enum ExportQuality {
  fast,
  balanced,
  high,
  uhd4k,
}

extension ExportQualityX on ExportQuality {
  String get label => switch (this) {
        ExportQuality.fast => 'Fast 720p',
        ExportQuality.balanced => 'Balanced 1080p',
        ExportQuality.high => 'High 1080p',
        ExportQuality.uhd4k => '4K Ultra',
      };

  /// Target export height.
  int get height => switch (this) {
        ExportQuality.fast => 720,
        ExportQuality.balanced => 1080,
        ExportQuality.high => 1080,
        ExportQuality.uhd4k => 2160,
      };

  int get fps => switch (this) {
        ExportQuality.fast => 24,
        ExportQuality.balanced => 30,
        ExportQuality.high => 30,
        ExportQuality.uhd4k => 30,
      };

  /// libx264 CRF — lower is higher quality.
  int get crf => switch (this) {
        ExportQuality.fast => 28,
        ExportQuality.balanced => 23,
        ExportQuality.high => 18,
        ExportQuality.uhd4k => 17,
      };

  String get preset => switch (this) {
        ExportQuality.fast => 'veryfast',
        ExportQuality.balanced => 'medium',
        ExportQuality.high => 'slow',
        ExportQuality.uhd4k => 'slow',
      };
}
