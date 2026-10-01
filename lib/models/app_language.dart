/// Supported speech / subtitle languages for AI captions.
class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.label,
    required this.nativeLabel,
  });

  final String code;
  final String label;
  final String nativeLabel;

  String get display => '$label · $nativeLabel';

  static const kurdishSorani = AppLanguage(
    code: 'ckb',
    label: 'Kurdish Sorani',
    nativeLabel: 'کوردی سۆرانی',
  );

  static const kurdishKurmanji = AppLanguage(
    code: 'kmr',
    label: 'Kurdish Kurmanji',
    nativeLabel: 'کوردیی کورمانجی',
  );

  static const arabic = AppLanguage(
    code: 'ar',
    label: 'Arabic',
    nativeLabel: 'العربية',
  );

  static const english = AppLanguage(
    code: 'en',
    label: 'English',
    nativeLabel: 'English',
  );

  static const persian = AppLanguage(
    code: 'fa',
    label: 'Persian',
    nativeLabel: 'فارسی',
  );

  static const turkish = AppLanguage(
    code: 'tr',
    label: 'Turkish',
    nativeLabel: 'Türkçe',
  );

  static const auto = AppLanguage(
    code: 'auto',
    label: 'Auto-detect',
    nativeLabel: 'خۆکار',
  );

  /// Spoken language in the video (includes auto-detect).
  static const List<AppLanguage> sourceOptions = [
    auto,
    kurdishSorani,
    kurdishKurmanji,
    arabic,
    english,
    persian,
    turkish,
  ];

  /// Subtitle output language (must be explicit).
  static const List<AppLanguage> subtitleOptions = [
    kurdishSorani,
    kurdishKurmanji,
    arabic,
    english,
    persian,
    turkish,
  ];

  static AppLanguage byCode(
    String code, {
    required List<AppLanguage> from,
    AppLanguage fallback = kurdishSorani,
  }) {
    for (final l in from) {
      if (l.code == code) return l;
    }
    return fallback;
  }
}
