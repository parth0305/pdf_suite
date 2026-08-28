import 'package:folio/domain/editing/pdf_text_editor.dart';
import 'package:folio/domain/editing/text_edit.dart';
import 'package:folio/domain/models/library_document.dart';

/// Reads and changes the words already on a page.
abstract interface class TextEditRepository {
  Future<List<EditableRun>> runsOn(int documentId, int pageIndex);

  /// What replacing [run]'s text would do, without doing it.
  Future<EditPlan> plan(int documentId, EditableRun run, String replacement);

  /// Applies the change, into a new document.
  Future<LibraryDocument> apply(
    int documentId,
    EditableRun run,
    String replacement,
  );
}
