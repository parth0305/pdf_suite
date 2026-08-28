import 'package:folio/domain/annotations/pdf_object_index.dart';

/// Something about a document that PDF/A does not allow.
enum PdfaIssue {
  /// A font the pages use is not embedded. PDF/A exists so a document renders
  /// the same in fifty years, and a font named but not carried is the single
  /// commonest reason one will not.
  fontNotEmbedded,

  /// Encryption. An archival document cannot require a password.
  encrypted,

  /// A cross-reference stream, which this converter cannot rewrite.
  xrefStream,

  /// LZW compression, withdrawn from PDF/A for patent reasons that have since
  /// expired but the ban has not.
  lzwCompression,

  /// A stream whose data lives in another file.
  externalStream,

  /// Embedded JavaScript. Removed rather than refused: Folio never runs it,
  /// and nothing about the page depends on it.
  javaScript,

  /// An attached file. Removed, and worth saying so before it happens.
  embeddedFile,

  /// `/NeedAppearances true`, which asks the reader to draw form values.
  /// Removed: Folio generates appearances, so the values stay visible.
  needAppearances,
}

/// What stands between a document and PDF/A.
class PdfaReport {
  const PdfaReport({required this.blockers, required this.removals});

  /// Issues that cannot be fixed here. Each carries what it applies to, so the
  /// user is told WHICH font is missing rather than that one is.
  final Map<PdfaIssue, List<String>> blockers;

  /// Issues the conversion fixes by taking something out.
  final Set<PdfaIssue> removals;

  bool get canConvert => blockers.isEmpty;
}

/// Blockers that cannot be repaired by rewriting, and removals that can.
///
/// Deliberately conservative: anything it cannot understand, it reports rather
/// than converts. A file wrongly stamped as PDF/A is worse than one honestly
/// refused, because the stamp is what an archive trusts.
PdfaReport checkPdfa(String pdfText) {
  final index = PdfObjectIndex.parse(pdfText);
  final blockers = <PdfaIssue, List<String>>{};
  final removals = <PdfaIssue>{};

  void block(PdfaIssue issue, String detail) =>
      (blockers[issue] ??= <String>[]).add(detail);

  if (index.usesXrefStream) {
    block(PdfaIssue.xrefStream, 'PDF 1.5 cross-reference stream');
  }
  if (RegExp(r'/Encrypt\s+\d+\s+\d+\s+R').hasMatch(pdfText)) {
    block(PdfaIssue.encrypted, 'password protected');
  }

  for (final number in index.objectNumbers) {
    final body = index.bodyOf(number)!;

    if (RegExp(r'/Type\s*/Font').hasMatch(body)) {
      final name =
          RegExp(r'/BaseFont\s*/([^\s/>\]]+)').firstMatch(body)?.group(1) ??
          'unnamed font';
      // A Type 0 font's descriptor lives on its descendant, so the absence of
      // /FontFile here is not proof of anything.
      final descendant = RegExp(
        r'/DescendantFonts\s*\[\s*(\d+)\s+\d+\s+R',
      ).firstMatch(body);

      final descriptorHolder = descendant == null
          ? body
          : index.bodyOf(int.parse(descendant.group(1)!)) ?? body;

      if (!_hasEmbeddedProgram(index, descriptorHolder)) {
        block(PdfaIssue.fontNotEmbedded, name);
      }
    }

    if (RegExp(r'/Filter[^\]>]*?/LZWDecode').hasMatch(body)) {
      block(PdfaIssue.lzwCompression, 'object $number');
    }
    // `/F` with a STRING value inside a stream dictionary means the data
    // lives in another file. The same key on an annotation is its flag field,
    // an integer, and confusing the two refuses every document carrying a
    // printable annotation.
    //
    // The `/Length` is what identifies a stream dictionary. Asking whether the
    // body contains the word `stream` cannot work: the index returns
    // dictionaries only, never their payloads, so that condition is one that
    // never becomes true.
    if (RegExp(r'/Length\s').hasMatch(body) &&
        RegExp(r'/F\s*\(').hasMatch(body)) {
      block(PdfaIssue.externalStream, 'object $number');
    }

    if (RegExp(r'/S\s*/JavaScript|/JS\s*[(<]').hasMatch(body)) {
      removals.add(PdfaIssue.javaScript);
    }
    if (RegExp(r'/Type\s*/Filespec|/EmbeddedFiles').hasMatch(body)) {
      removals.add(PdfaIssue.embeddedFile);
    }
    if (RegExp(r'/NeedAppearances\s+true').hasMatch(body)) {
      removals.add(PdfaIssue.needAppearances);
    }
  }

  return PdfaReport(blockers: blockers, removals: removals);
}

/// Whether a font descriptor carries the font program itself.
bool _hasEmbeddedProgram(PdfObjectIndex index, String body) {
  final descriptor = RegExp(
    r'/FontDescriptor\s+(\d+)\s+\d+\s+R',
  ).firstMatch(body);

  final text = descriptor == null
      ? body
      : index.bodyOf(int.parse(descriptor.group(1)!)) ?? body;

  return RegExp(r'/FontFile[23]?\s').hasMatch(text);
}
