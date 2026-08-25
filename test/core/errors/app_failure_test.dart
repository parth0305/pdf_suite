import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';

void main() {
  group('AppFailure', () {
    test('every variant exposes a stable non-empty code', () {
      const failures = <AppFailure>[
        DocumentCorrupt(),
        DocumentMoved(),
        PermissionRevoked(),
        PasswordRequired(),
        WrongPassword(),
        UnsupportedFeature(),
        StorageFull(),
        UnknownFailure(),
      ];
      for (final f in failures) {
        expect(
          f.code,
          isNotEmpty,
          reason: '${f.runtimeType} has an empty code',
        );
      }
      final codes = failures.map((f) => f.code).toSet();
      expect(codes.length, failures.length, reason: 'codes must be unique');
    });

    test(
      'technical detail is retained for logging but is not the user message',
      () {
        const f = DocumentCorrupt(technicalDetail: 'xref offset 91827 invalid');
        expect(f.technicalDetail, 'xref offset 91827 invalid');
      },
    );

    test('technical detail defaults to null', () {
      expect(const DocumentMoved().technicalDetail, isNull);
    });
  });
}
