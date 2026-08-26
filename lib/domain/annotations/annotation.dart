import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';

part 'drawing_annotation.dart';
part 'text_markup.dart';

/// Anything that can be staged and written into a PDF as an annotation object.
///
/// Sealed so the writer's switch over annotation kinds is exhaustive: adding a
/// kind without teaching the writer about it becomes a compile error. Dart only
/// permits a sealed type to be extended inside its own library, which is why
/// the subclasses are `part` files rather than separate imports.
sealed class Annotation {
  const Annotation();

  /// Zero-based page this annotation belongs to.
  int get pageIndex;

  /// The PDF annotation subtype name, without the leading slash.
  String get pdfSubtype;
}
