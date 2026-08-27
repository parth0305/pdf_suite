import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class Collections extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// A signature the user drew once, reusable on any document.
///
/// [strokes] is JSON: a list of stroke point lists, normalised into a unit box
/// with y increasing upward. [kind] and [imageBytes] exist so a photographed
/// signature can land later without migrating what is already stored.
class Signatures extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get label => text()();
  TextColumn get kind => text().withDefault(const Constant('drawn'))();
  TextColumn get strokes => text()();
  RealColumn get aspectRatio => real()();
  BlobColumn get imageBytes => blob().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Documents extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Serialized DocumentRef (see DocumentRef.encode). Never a bare path.
  TextColumn get refPayload => text()();

  TextColumn get displayName => text()();
  IntColumn get sizeBytes => integer()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  IntColumn get pageCount => integer().nullable()();

  /// True when Folio itself produced this file, which makes it safe to rewrite
  /// in place. Imported copies are never rewritten.
  BoolColumn get createdByFolio =>
      boolean().withDefault(const Constant(false))();

  /// Null means the document sits at the library root.
  ///
  /// Folders are virtual: managed files are stored content-addressed and flat,
  /// so a move is an UPDATE rather than a file operation that could fail
  /// halfway. onDelete setNull guarantees deleting a folder can never cascade
  /// into deleting documents.
  IntColumn get collectionId => integer().nullable().references(
    Collections,
    #id,
    onDelete: KeyAction.setNull,
  )();
}

/// Rules that run when a document enters the library.
///
/// `protect` is deliberately not a storable action: a rule that runs
/// unattended would need its password at rest, which is what protection exists
/// to avoid.
@DataClassName('AutomationRuleRow')
class AutomationRules extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// One of AutomationAction's names.
  TextColumn get action => text()();

  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  TextColumn get nameContains => text().nullable()();
  IntColumn get minSizeBytes => integer().nullable()();
  TextColumn get watermarkText => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [Documents, Collections, Signatures, AutomationRules])
class AppDatabase extends _$AppDatabase {
  AppDatabase()
    : super(
        driftDatabase(
          name: 'folio',
          // Application Support, not Documents. UIFileSharingEnabled makes
          // Documents visible in the Files app, where a user could delete the
          // database and lose their whole library. Matches AppDirectories.
          native: const DriftNativeOptions(
            databaseDirectory: getApplicationSupportDirectory,
          ),
        ),
      );

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(collections);
        await m.addColumn(documents, documents.collectionId);
      }
      if (from < 3) {
        // Existing rows default to false, so documents created before this
        // column existed are treated as imported and produce a new document
        // on save. That is the safe direction.
        await m.addColumn(documents, documents.createdByFolio);
      }
      if (from < 4) {
        await m.createTable(signatures);
      }
      if (from < 5) {
        await m.createTable(automationRules);
      }
    },
    beforeOpen: (details) async {
      // Required for onDelete actions to be honoured by SQLite.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
