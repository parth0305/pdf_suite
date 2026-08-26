part of 'annotation.dart';

enum StampPreset { approved, rejected, draft, confidential, reviewed, urgent }

/// One of a fixed set of preset marks.
///
/// Unlike a note, a /Stamp renders nothing without an appearance stream -
/// probed on device: zero pixels changed - so one is always generated.
final class Stamp extends Annotation {
  const Stamp({
    required this.preset,
    required this.pageIndex,
    required this.anchorPt,
  });

  final StampPreset preset;

  @override
  final int pageIndex;

  /// Top-left of the box, in PDF user space.
  final PdfPoint anchorPt;

  @override
  String get pdfSubtype => 'Stamp';

  String get label => switch (preset) {
    StampPreset.approved => 'APPROVED',
    StampPreset.rejected => 'REJECTED',
    StampPreset.draft => 'DRAFT',
    StampPreset.confidential => 'CONFIDENTIAL',
    StampPreset.reviewed => 'REVIEWED',
    StampPreset.urgent => 'URGENT',
  };

  int get colorArgb => switch (preset) {
    StampPreset.approved => 0xFF388E3C,
    StampPreset.rejected => 0xFFD32F2F,
    StampPreset.draft => 0xFF616161,
    StampPreset.confidential => 0xFFD32F2F,
    StampPreset.reviewed => 0xFF1976D2,
    StampPreset.urgent => 0xFFF9A825,
  };

  static const double fontSizePt = 14;
  static const double paddingPt = 8;

  /// Sized from the label rather than measured. 0.75 em is a safe upper bound
  /// for uppercase Helvetica, so the text always fits by construction; a fixed
  /// width would clip CONFIDENTIAL and waste space on DRAFT. Carrying a width
  /// table for a font we do not embed is not worth the accuracy.
  double get widthPt => 2 * paddingPt + label.length * fontSizePt * 0.75;

  double get heightPt => fontSizePt + 2 * paddingPt;
}
