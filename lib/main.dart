import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/app.dart';
import 'package:folio/core/storage/app_directories.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/data/local/signature_dao.dart';
import 'package:folio/data/repositories/annotation_edit_repository_impl.dart';
import 'package:folio/data/repositories/annotation_repository_impl.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/page_operations_repository_impl.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:folio/engine/pdfrx_page_editor.dart';
import 'package:folio/features/home/providers.dart';
import 'package:folio/features/pages/providers.dart';
import 'package:folio/data/repositories/signature_repository_impl.dart';
import 'package:folio/features/viewer/annotation_edit_providers.dart';
import 'package:folio/features/viewer/annotation_providers.dart';
import 'package:folio/features/viewer/signature_providers.dart';
import 'package:pdfrx/pdfrx.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();

  const dirs = AppDirectories();
  final libraryRoot = await dirs.libraryRoot();
  final db = AppDatabase();

  final library = LibraryRepositoryImpl(
    dao: LibraryDao(db),
    writer: SafeFileWriter(),
    libraryRoot: libraryRoot,
  );

  final documentWriter = DocumentWriter(
    library: library,
    writer: SafeFileWriter(),
    libraryRoot: libraryRoot,
  );
  final annotations = AnnotationRepositoryImpl(
    library: library,
    documents: documentWriter,
  );
  final signatures = SignatureRepositoryImpl(dao: SignatureDao(db));
  final annotationEdits = AnnotationEditRepositoryImpl(
    library: library,
    documents: documentWriter,
  );

  // One engine instance shared by the editor, so the handles it opens are the
  // same ones the editor resolves pages from.
  final engine = PdfrxEngine();
  final pageOperations = PageOperationsRepositoryImpl(
    library: library,
    writer: SafeFileWriter(),
    libraryRoot: libraryRoot,
    editor: PdfrxPageEditor(engine),
    openSource: (doc) async =>
        engine.open(FileSource(await library.resolveReadablePath(doc))),
    closeSource: engine.close,
  );

  runApp(
    ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(library),
        pageOperationsRepositoryProvider.overrideWithValue(pageOperations),
        annotationRepositoryProvider.overrideWithValue(annotations),
        annotationEditRepositoryProvider.overrideWithValue(annotationEdits),
        signatureRepositoryProvider.overrideWithValue(signatures),
      ],
      child: const FolioApp(),
    ),
  );
}
