import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/app.dart';
import 'package:folio/core/storage/app_directories.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/features/home/providers.dart';
import 'package:pdfrx/pdfrx.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();

  const dirs = AppDirectories();
  final libraryRoot = await dirs.libraryRoot();
  final db = AppDatabase();

  runApp(
    ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(
          LibraryRepositoryImpl(
            dao: LibraryDao(db),
            writer: SafeFileWriter(),
            libraryRoot: libraryRoot,
          ),
        ),
      ],
      child: const FolioApp(),
    ),
  );
}
