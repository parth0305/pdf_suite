import 'dart:io';

import 'package:folio/data/local/automation_dao.dart';
import 'package:folio/domain/automation/automation_rule.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/automation_repository.dart';
import 'package:folio/domain/repositories/compression_repository.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/repositories/ocr_repository.dart';
import 'package:folio/domain/repositories/watermark_repository.dart';
import 'package:folio/domain/watermark/watermark.dart';

class AutomationRepositoryImpl implements AutomationRepository {
  AutomationRepositoryImpl({
    required AutomationDao dao,
    required LibraryRepository library,
    required CompressionRepository compression,
    required OcrRepository ocr,
    required WatermarkRepository watermark,
  }) : _dao = dao,
       _library = library,
       _compression = compression,
       _ocr = ocr,
       _watermark = watermark;

  final AutomationDao _dao;
  final LibraryRepository _library;
  final CompressionRepository _compression;
  final OcrRepository _ocr;
  final WatermarkRepository _watermark;

  @override
  Future<List<AutomationRule>> rules() => _dao.all();

  @override
  Future<AutomationRule> add({
    required AutomationAction action,
    String? nameContains,
    int? minSizeBytes,
    String? watermarkText,
  }) => _dao.insertRule(
    action: action,
    nameContains: nameContains,
    minSizeBytes: minSizeBytes,
    watermarkText: watermarkText,
  );

  @override
  Future<void> setEnabled(int id, {required bool enabled}) =>
      _dao.setEnabled(id, enabled: enabled);

  @override
  Future<void> remove(int id) => _dao.deleteRule(id);

  @override
  Future<LibraryDocument> runOnImport(LibraryDocument document) async {
    var current = document;

    for (final rule in await _dao.all()) {
      // `isRunnable` is checked here as well as when a rule is created. No
      // test can distinguish it: without the check a watermark rule with no
      // text throws on its null assertion and the catch below swallows it,
      // giving the same outcome. It is kept because relying on a thrown
      // exception for ordinary control flow would mean a malformed rule costs
      // an exception on every import, forever.
      if (!rule.isRunnable || !rule.matches(current)) continue;

      try {
        current = await _apply(rule, current);
      } on Object {
        // Automation runs with nobody watching. An import must not fail
        // because a rule did, and the document is already safely in the
        // library - so the rule is abandoned and the rest continue.
        continue;
      }
    }

    return current;
  }

  Future<LibraryDocument> _apply(
    AutomationRule rule,
    LibraryDocument document,
  ) async {
    // A watermark changes what the page looks like, so it can never replace
    // the document it came from.
    if (!rule.action.isLossless) {
      return _watermark.apply(
        document.id,
        Watermark(text: rule.watermarkText!),
      );
    }

    final produced = switch (rule.action) {
      AutomationAction.compress => await _compressed(document),
      AutomationAction.ocr => await _ocr.recognise(document.id),
      AutomationAction.watermark => null,
    };
    if (produced == null) return document;

    return _replaceOrKeep(document, produced);
  }

  Future<LibraryDocument?> _compressed(LibraryDocument document) async {
    final result = await _compression.analyse(document.id);
    // Nothing to gain is not a failure, and not a reason to make a copy.
    if (!result.worthDoing) return null;

    return _compression.save(document.id, result);
  }

  /// Folds a lossless result back into the original row where that is safe,
  /// and deletes the intermediate document the operation created.
  ///
  /// **Only for managed documents.** A document opened in place points at the
  /// user's own file on disk; rewriting that would modify a file outside
  /// Folio's library, which nothing in this project does. Those keep the new
  /// document instead.
  Future<LibraryDocument> _replaceOrKeep(
    LibraryDocument original,
    LibraryDocument produced,
  ) async {
    if (!original.isManaged) return produced;

    final bytes = await File(
      await _library.resolveReadablePath(produced),
    ).readAsBytes();

    final replaced = await _library.replaceManagedContent(
      documentId: original.id,
      bytes: bytes,
    );

    // The operation produced its own library row; without removing it the
    // library gains an entry per rule per import, which is the flooding this
    // design exists to avoid.
    await _library.delete(produced.id);

    return replaced;
  }
}
