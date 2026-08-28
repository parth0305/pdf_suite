import 'dart:io';
import 'dart:ui' show Rect;

import 'package:folio/domain/sharing/document_export.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a document to the operating system.
///
/// The one place in Folio where a document leaves the device. Behind an
/// interface so everything around it is testable without a printer or a share
/// sheet.
abstract interface class PlatformExport {
  Future<void> print(DocumentExport export);
  Future<void> share(DocumentExport export, {Rect? origin});

  /// Hands several already-written files to the share sheet.
  ///
  /// Used by page export, where the files exist on disk already and there is
  /// no single document to describe.
  Future<void> shareFiles(List<String> paths, {Rect? origin});
}

class SystemExport implements PlatformExport {
  const SystemExport();

  @override
  Future<void> print(DocumentExport export) => Printing.layoutPdf(
    // The bytes are handed over unchanged. Folio does not re-render or
    // re-encode the document to print it: what comes out of the printer is
    // the document in the library, not a copy of it.
    onLayout: (_) async => export.bytes,
    name: export.fileName,
  );

  @override
  Future<void> shareFiles(List<String> paths, {Rect? origin}) async {
    if (paths.isEmpty) return;

    await SharePlus.instance.share(
      ShareParams(
        files: [for (final p in paths) XFile(p)],
        sharePositionOrigin: origin,
      ),
    );
  }

  @override
  Future<void> share(DocumentExport export, {Rect? origin}) async {
    // A real file on disk, because the share sheet hands a path to another
    // application. It goes in the temp directory, not the library: this is a
    // copy on its way out, not a document.
    final dir = await Directory.systemTemp.createTemp('folio_share');
    final file = File('${dir.path}/${export.fileName}')
      ..writeAsBytesSync(export.bytes);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        // The name travels with it: two similarly named documents in the
        // library is the realistic mistake, and the share sheet is the last
        // point at which it can be noticed.
        fileNameOverrides: [export.fileName],
        // iPad requires an anchor for the share sheet; every other platform
        // ignores it.
        sharePositionOrigin: origin,
      ),
    );
  }
}
