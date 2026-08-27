import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/ocr/hocr_parser.dart';

/// A cut-down but structurally faithful hOCR document. The shape matches what
/// Tesseract 4 emitted on a real device during the SP-6b probe.
const hocr = '''
<div class='ocr_page' id='page_1' title='image "x"; bbox 0 0 1654 2339'>
  <div class='ocr_carea' id='block_1_1' title="bbox 100 200 1500 400">
   <p class='ocr_par' dir='ltr' id='par_1_1' title="bbox 100 200 1500 400">
    <span class='ocr_line' id='line_1_1' title="bbox 100 200 900 260; baseline 0 -12">
     <span class='ocrx_word' id='word_1_1' title='bbox 100 200 400 260; x_wconf 96'>Confidential</span>
     <span class='ocrx_word' id='word_1_2' title='bbox 420 200 620 260; x_wconf 95'>Invoice</span>
    </span>
    <span class='ocr_line' id='line_1_2' title="bbox 100 300 1400 360; baseline 0 -12">
     <span class='ocrx_word' id='word_1_3' title='bbox 100 300 300 360; x_wconf 90'>Acme</span>
     <span class='ocrx_word' id='word_1_4' title='bbox 320 300 700 360; x_wconf 88'>REDACT-ME-9931</span>
    </span>
   </p>
  </div>
</div>
''';

void main() {
  group('parseHocr', () {
    test('reads every word', () {
      final page = parseHocr(hocr);

      expect(page.words.map((w) => w.text), [
        'Confidential',
        'Invoice',
        'Acme',
        'REDACT-ME-9931',
      ]);
    });

    test('reads each word box', () {
      final word = parseHocr(hocr).words.first;

      expect(word.left, 100);
      expect(word.top, 200);
      expect(word.right, 400);
      expect(word.bottom, 260);
      expect(word.width, 300);
      expect(word.height, 60);
    });

    // The line grouping is what a plain-text fallback uses, and what makes the
    // extracted text read as a document rather than a word list.
    test('groups words into lines', () {
      final page = parseHocr(hocr);

      expect(page.lines, ['Confidential Invoice', 'Acme REDACT-ME-9931']);
    });

    test('reports that it has positions', () {
      expect(parseHocr(hocr).hasPositions, isTrue);
    });

    // A heading is emitted as ocr_header, not ocr_line. Matching only ocr_line
    // silently loses every title in the document - which looks like OCR simply
    // failing to read large text.
    test('a heading line is not dropped', () {
      const withHeader = '''
<span class='ocr_header' id='line_h' title="bbox 0 0 100 20">
 <span class='ocrx_word' id='w' title='bbox 0 0 50 20; x_wconf 90'>Title</span>
</span>
<span class='ocr_line' id='line_1' title="bbox 0 30 100 50">
 <span class='ocrx_word' id='w2' title='bbox 0 30 50 50; x_wconf 90'>Body</span>
</span>
''';

      expect(parseHocr(withHeader).lines, ['Title', 'Body']);
    });

    test('HTML entities in recognised text are decoded', () {
      const entities = '''
<span class='ocr_line' id='l' title="bbox 0 0 100 20">
 <span class='ocrx_word' id='w' title='bbox 0 0 50 20'>A&amp;B</span>
 <span class='ocrx_word' id='w2' title='bbox 60 0 90 20'>&lt;tag&gt;</span>
</span>
''';

      expect(parseHocr(entities).words.map((w) => w.text), ['A&B', '<tag>']);
    });

    test('a word with no bbox is skipped rather than placed at the origin', () {
      const noBox = '''
<span class='ocr_line' id='l' title="bbox 0 0 100 20">
 <span class='ocrx_word' id='w' title='x_wconf 90'>Floating</span>
 <span class='ocrx_word' id='w2' title='bbox 0 0 50 20'>Placed</span>
</span>
''';

      expect(parseHocr(noBox).words.map((w) => w.text), ['Placed']);

      // And it must not survive in the line text either. `lines` feeds the
      // fallback path and `words` the positioned one; if they disagree, the
      // same scan says different things on different platforms.
      expect(parseHocr(noBox).lines, ['Placed']);
    });

    test('an empty word contributes nothing', () {
      const blank = '''
<span class='ocr_line' id='l' title="bbox 0 0 100 20">
 <span class='ocrx_word' id='w' title='bbox 0 0 50 20'>   </span>
 <span class='ocrx_word' id='w2' title='bbox 60 0 90 20'>Real</span>
</span>
''';

      expect(parseHocr(blank).words.map((w) => w.text), ['Real']);
      expect(parseHocr(blank).lines, ['Real']);
    });

    test('hOCR with no words at all yields an empty page', () {
      final page = parseHocr('<div class="ocr_page"></div>');

      expect(page.words, isEmpty);
      expect(page.lines, isEmpty);
      expect(page.hasPositions, isFalse);
    });
  });
}
