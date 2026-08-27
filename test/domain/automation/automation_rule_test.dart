import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/automation/automation_rule.dart';
import 'package:folio/domain/models/document_ref.dart';
import 'package:folio/domain/models/library_document.dart';

LibraryDocument doc({String name = 'Invoice.pdf', int size = 1000}) =>
    LibraryDocument(
      id: 1,
      ref: const ManagedRef(relativePath: 'a/b.pdf', contentHash: 'h'),
      displayName: name,
      sizeBytes: size,
      addedAt: DateTime(2026),
      isFavorite: false,
    );

const compress = AutomationRule(id: 1, action: AutomationAction.compress);

void main() {
  group('matching', () {
    test('a rule with no conditions matches everything', () {
      expect(compress.matches(doc()), isTrue);
      expect(compress.matches(doc(name: 'Anything.pdf', size: 1)), isTrue);
    });

    // A disabled rule must match nothing at all: the switch is the user's way
    // of stopping it without losing how they set it up.
    test('a disabled rule matches nothing', () {
      expect(compress.copyWith(enabled: false).matches(doc()), isFalse);
    });

    test('nameContains is case-insensitive', () {
      const rule = AutomationRule(
        id: 1,
        action: AutomationAction.compress,
        nameContains: 'INVOICE',
      );

      expect(rule.matches(doc(name: 'my invoice 2026.pdf')), isTrue);
      expect(rule.matches(doc(name: 'Receipt.pdf')), isFalse);
    });

    // An empty condition is not a condition. A blank text field should not
    // silently stop a rule from ever running.
    test('a blank nameContains is not a condition', () {
      const rule = AutomationRule(
        id: 1,
        action: AutomationAction.compress,
        nameContains: '   ',
      );

      expect(rule.matches(doc(name: 'Anything.pdf')), isTrue);
    });

    test('minSizeBytes excludes smaller documents', () {
      const rule = AutomationRule(
        id: 1,
        action: AutomationAction.compress,
        minSizeBytes: 5000,
      );

      expect(rule.matches(doc(size: 5000)), isTrue, reason: 'inclusive');
      expect(rule.matches(doc(size: 4999)), isFalse);
    });

    test('conditions are ANDed', () {
      const rule = AutomationRule(
        id: 1,
        action: AutomationAction.compress,
        nameContains: 'scan',
        minSizeBytes: 5000,
      );

      expect(rule.matches(doc(name: 'scan.pdf', size: 6000)), isTrue);
      expect(rule.matches(doc(name: 'scan.pdf', size: 100)), isFalse);
      expect(rule.matches(doc(name: 'invoice.pdf', size: 6000)), isFalse);
    });
  });

  group('losslessness decides whether the copy is rewritten', () {
    test('compress and OCR are lossless', () {
      expect(AutomationAction.compress.isLossless, isTrue);
      expect(AutomationAction.ocr.isLossless, isTrue);
    });

    // Replacing a document with a watermarked version destroys the unmarked
    // one. It has to produce a new document.
    test('watermark is not', () {
      expect(AutomationAction.watermark.isLossless, isFalse);
    });
  });

  group('runnability', () {
    // A watermark rule with no text throws at run time, on a document the user
    // was not asked about. It must never be allowed to run.
    test('a watermark rule needs text', () {
      const blank = AutomationRule(id: 1, action: AutomationAction.watermark);

      expect(blank.isRunnable, isFalse);
      expect(
        blank.copyWith(watermarkText: '  ').isRunnable,
        isFalse,
        reason: 'whitespace is not a watermark',
      );
      expect(blank.copyWith(watermarkText: 'DRAFT').isRunnable, isTrue);
    });

    test('the other actions need nothing extra', () {
      expect(compress.isRunnable, isTrue);
      expect(
        const AutomationRule(id: 1, action: AutomationAction.ocr).isRunnable,
        isTrue,
      );
    });
  });

  // Automating this would mean storing the password to use it unattended,
  // which is exactly what protection exists to avoid.
  test('protect is not an automatable action', () {
    expect(
      AutomationAction.values.map((a) => a.name),
      isNot(contains('protect')),
    );
  });
}
