import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class Collections extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
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

@DriftDatabase(tables: [Documents, Collections])
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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(collections);
        await m.addColumn(documents, documents.collectionId);
      }
    },
    beforeOpen: (details) async {
      // Required for onDelete actions to be honoured by SQLite.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
