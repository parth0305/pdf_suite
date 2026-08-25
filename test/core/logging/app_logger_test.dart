import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/core/logging/app_logger.dart';

void main() {
  late AppLogger logger;

  setUp(() => logger = AppLogger.forTesting());

  group('AppLogger', () {
    test('records an operation with size and result', () {
      logger.operationStart('open_document', fileSizeBytes: 1539);
      logger.operationEnd(
        'open_document',
        success: true,
        elapsed: const Duration(milliseconds: 9),
      );

      expect(logger.buffer, hasLength(2));
      expect(logger.buffer.last.message, contains('open_document'));
      expect(logger.buffer.last.message, contains('success'));
    });

    test('records the failure code, not the user message', () {
      logger.operationEnd(
        'open_document',
        success: false,
        failure: const DocumentCorrupt(technicalDetail: 'xref offset bad'),
      );

      final line = logger.buffer.last.message;
      expect(line, contains('document_corrupt'));
      expect(line, contains('xref offset bad'));
    });

    test('hashIdentity is stable and does not leak the input', () {
      const path = '/Users/someone/Documents/Salary Slip March.pdf';
      final a = logger.hashIdentity(path);
      final b = logger.hashIdentity(path);

      expect(a, b, reason: 'must be deterministic');
      expect(a, isNot(contains('Salary')));
      expect(a, isNot(contains('someone')));
      expect(a.length, 16, reason: 'truncated hash keeps logs readable');
    });

    test('different inputs hash differently', () {
      expect(logger.hashIdentity('a.pdf'), isNot(logger.hashIdentity('b.pdf')));
    });
  });
}
