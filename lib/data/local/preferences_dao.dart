import 'package:drift/drift.dart';
import 'package:folio/data/local/app_database.dart';

part 'preferences_dao.g.dart';

@DriftAccessor(tables: [Preferences])
class PreferencesDao extends DatabaseAccessor<AppDatabase>
    with _$PreferencesDaoMixin {
  PreferencesDao(super.db);

  Future<String?> read(String key) async {
    final row = await (select(
      preferences,
    )..where((t) => t.key.equals(key))).getSingleOrNull();

    return row?.value;
  }

  Future<void> write(String key, String value) => into(
    preferences,
  ).insertOnConflictUpdate(PreferencesCompanion.insert(key: key, value: value));
}
