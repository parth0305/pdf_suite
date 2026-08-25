import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/constants/app_config.dart';

void main() {
  group('AppConfig', () {
    test('defaults to development when no dart-define is supplied', () {
      expect(AppConfig.current.environment, 'development');
    });

    test('production config disables verbose logging', () {
      const prod = AppConfig(environment: 'production', verboseLogging: false);
      expect(prod.verboseLogging, isFalse);
      expect(prod.isProduction, isTrue);
    });

    test('development config is not production', () {
      const dev = AppConfig(environment: 'development', verboseLogging: true);
      expect(dev.isProduction, isFalse);
    });
  });
}
