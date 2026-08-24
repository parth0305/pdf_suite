import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

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
}

@DriftDatabase(tables: [Documents])
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
  int get schemaVersion => 1;
}
