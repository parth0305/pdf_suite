/// What a reader is permitted to do with a protected document.
///
/// PDF permissions are **advisory**. They are recorded in the document and
/// honoured by well-behaved viewers, and any viewer may ignore them entirely.
/// Folio says so wherever it offers them: a permission is a request, not a
/// control.
class PdfPermissions {
  const PdfPermissions({
    this.printing = true,
    this.copying = true,
    this.modifying = true,
    this.annotating = true,
  });

  /// Everything allowed, which is what a document with only a user password
  /// gets.
  static const all = PdfPermissions();

  final bool printing;
  final bool copying;
  final bool modifying;
  final bool annotating;

  /// The `/P` bit field, per ISO 32000-1 Table 22.
  ///
  /// Bits are numbered from 1 and the field is a signed 32-bit integer, so it
  /// starts as all-ones and each denied permission clears its bit. Bits 1 and
  /// 2 are reserved and must be zero; every bit above 12 must stay set.
  int get bits {
    var p = -1;
    p &= ~1;
    p &= ~2;

    if (!printing) {
      p &= ~4;
      // High-quality printing cannot outlive printing itself.
      p &= ~2048;
    }
    if (!modifying) {
      p &= ~8;
      // Assembling a document is a form of modifying it.
      p &= ~1024;
    }
    if (!copying) p &= ~16;
    if (!annotating) {
      p &= ~32;
      // Filling a form field is an annotation operation.
      p &= ~256;
    }

    return p;
  }
}
