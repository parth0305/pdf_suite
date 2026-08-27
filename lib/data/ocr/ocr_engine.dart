import 'dart:io';

import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:folio/domain/ocr/hocr_parser.dart';
import 'package:folio/domain/ocr/ocr_word.dart';

/// Recognises text in an image file.
///
/// An interface, not a direct plugin call, so the pipeline around it is
/// testable without a native OCR engine.
abstract interface class OcrEngine {
  Future<OcrPage> recognise(String imagePath);
}

/// Tesseract 4, via `flutter_tesseract_ocr`.
///
/// Word positions come from hOCR **on Android only**. On iOS the plugin's
/// `extractHocr` blocks the platform thread so completely that even a Dart
/// timeout never fires - measured on a simulator, not assumed - so that
/// platform gets plain text and the layer falls back to approximate placement.
class TesseractOcrEngine implements OcrEngine {
  const TesseractOcrEngine({this.supportsHocr});

  /// Overridable for tests. Null means "decide from the platform".
  final bool? supportsHocr;

  bool get _hocr => supportsHocr ?? Platform.isAndroid;

  @override
  Future<OcrPage> recognise(String imagePath) async {
    if (_hocr) {
      return parseHocr(
        await FlutterTesseractOcr.extractHocr(imagePath, language: 'eng'),
      );
    }

    final text = await FlutterTesseractOcr.extractText(
      imagePath,
      language: 'eng',
    );

    return OcrPage(
      lines: [
        for (final line in text.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ],
    );
  }
}
