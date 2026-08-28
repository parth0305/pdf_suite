import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/app.dart';
import 'package:folio/core/storage/app_directories.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/data/repositories/redaction_repository_impl.dart';
import 'package:folio/data/ocr/ocr_engine.dart';
import 'package:folio/data/local/automation_dao.dart';
import 'package:folio/data/local/preferences_dao.dart';
import 'package:folio/data/repositories/automation_repository_impl.dart';
import 'package:folio/data/repositories/export_repository_impl.dart';
import 'package:folio/data/repositories/image_export_repository_impl.dart';
import 'package:folio/data/repositories/numbering_repository_impl.dart';
import 'package:folio/data/repositories/metadata_repository_impl.dart';
import 'package:folio/data/repositories/unlock_repository_impl.dart';
import 'package:folio/data/sharing/platform_export.dart';
import 'package:folio/data/repositories/batch_repository_impl.dart';
import 'package:folio/data/repositories/compression_repository_impl.dart';
import 'package:folio/data/repositories/ocr_repository_impl.dart';
import 'package:folio/data/repositories/scanner_repository_impl.dart';
import 'package:folio/data/scanner/image_source.dart';
import 'package:folio/data/local/signature_dao.dart';
import 'package:folio/data/repositories/annotation_edit_repository_impl.dart';
import 'package:folio/data/repositories/annotation_repository_impl.dart';
import 'package:folio/data/repositories/crop_repository_impl.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/page_operations_repository_impl.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:folio/engine/pdfrx_page_editor.dart';
import 'package:folio/features/home/providers.dart';
import 'package:folio/features/pages/providers.dart';
import 'package:folio/data/repositories/signature_repository_impl.dart';
import 'package:folio/data/repositories/protection_repository_impl.dart';
import 'package:folio/data/repositories/watermark_repository_impl.dart';
import 'package:folio/features/viewer/annotation_edit_providers.dart';
import 'package:folio/features/viewer/annotation_providers.dart';
import 'package:folio/features/viewer/signature_providers.dart';
import 'package:folio/features/viewer/protection_providers.dart';
import 'package:folio/features/viewer/redaction_providers.dart';
import 'package:folio/features/scanner/scanner_providers.dart';
import 'package:folio/features/automation/automation_providers.dart';
import 'package:folio/features/settings/settings_providers.dart';
import 'package:folio/features/viewer/export_providers.dart';
import 'package:folio/features/viewer/image_export_providers.dart';
import 'package:folio/features/viewer/crop_providers.dart';
import 'package:folio/features/viewer/numbering_providers.dart';
import 'package:folio/features/viewer/metadata_providers.dart';
import 'package:folio/features/viewer/unlock_providers.dart';
import 'package:folio/features/batch/batch_providers.dart';
import 'package:folio/features/viewer/compression_providers.dart';
import 'package:folio/features/viewer/ocr_providers.dart';
import 'package:folio/features/viewer/watermark_providers.dart';
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
  final protection = ProtectionRepositoryImpl(
    library: library,
    documents: documentWriter,
  );
  final scanner = ScannerRepositoryImpl(documents: documentWriter);
  final compression = CompressionRepositoryImpl(
    library: library,
    documents: documentWriter,
  );
  final ocr = OcrRepositoryImpl(
    library: library,
    documents: documentWriter,
    engine: PdfrxEngine(),
    ocr: const TesseractOcrEngine(),
  );
  final redaction = RedactionRepositoryImpl(
    library: library,
    documents: documentWriter,
    engine: PdfrxEngine(),
  );
  final watermarks = WatermarkRepositoryImpl(
    library: library,
    documents: documentWriter,
  );
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
        watermarkRepositoryProvider.overrideWithValue(watermarks),
        protectionRepositoryProvider.overrideWithValue(protection),
        redactionRepositoryProvider.overrideWithValue(redaction),
        scannerRepositoryProvider.overrideWithValue(scanner),
        ocrRepositoryProvider.overrideWithValue(ocr),
        compressionRepositoryProvider.overrideWithValue(compression),
        preferencesDaoProvider.overrideWithValue(PreferencesDao(db)),
        cropRepositoryProvider.overrideWithValue(
          CropRepositoryImpl(
            library: library,
            documents: documentWriter,
            engine: PdfrxEngine(),
          ),
        ),
        numberingRepositoryProvider.overrideWithValue(
          NumberingRepositoryImpl(library: library, documents: documentWriter),
        ),
        imageExportRepositoryProvider.overrideWithValue(
          ImageExportRepositoryImpl(library: library, engine: PdfrxEngine()),
        ),
        unlockRepositoryProvider.overrideWithValue(
          UnlockRepositoryImpl(library: library, documents: documentWriter),
        ),
        metadataRepositoryProvider.overrideWithValue(
          MetadataRepositoryImpl(library: library, documents: documentWriter),
        ),
        exportRepositoryProvider.overrideWithValue(
          ExportRepositoryImpl(library: library),
        ),
        platformExportProvider.overrideWithValue(const SystemExport()),
        automationRepositoryProvider.overrideWithValue(
          AutomationRepositoryImpl(
            dao: AutomationDao(db),
            library: library,
            compression: compression,
            ocr: ocr,
            watermark: watermarks,
          ),
        ),
        batchRepositoryProvider.overrideWithValue(
          BatchRepositoryImpl(
            compression: compression,
            ocr: ocr,
            watermark: watermarks,
            protection: protection,
          ),
        ),
        scanImageSourceProvider.overrideWithValue(PlatformImageSource()),
      ],
      child: const FolioApp(),
    ),
  );
}
