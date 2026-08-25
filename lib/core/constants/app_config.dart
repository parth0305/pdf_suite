/// Build-time configuration, supplied via `--dart-define-from-file`.
///
/// Defaults to development so that a bare `flutter run` works without flags.
class AppConfig {
  const AppConfig({required this.environment, required this.verboseLogging});

  final String environment;
  final bool verboseLogging;

  bool get isProduction => environment == 'production';

  static const AppConfig current = AppConfig(
    environment: String.fromEnvironment('APP_ENV', defaultValue: 'development'),
    verboseLogging: bool.fromEnvironment('VERBOSE_LOGGING', defaultValue: true),
  );
}
