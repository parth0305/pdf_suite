import 'package:flutter/material.dart';
import 'package:folio/core/theme/app_theme.dart';
import 'package:folio/features/home/library_screen.dart';
import 'package:folio/l10n/app_localizations.dart';
import 'package:folio/widgets/adaptive_scaffold.dart';

class FolioApp extends StatefulWidget {
  const FolioApp({super.key});

  @override
  State<FolioApp> createState() => _FolioAppState();
}

class _FolioAppState extends State<FolioApp> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context)!;
          return AdaptiveScaffold(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              AdaptiveDestination(
                icon: const Icon(Icons.folder_outlined),
                label: l10n.libraryTitle,
              ),
              AdaptiveDestination(
                icon: const Icon(Icons.settings_outlined),
                label: l10n.settingsLabel,
              ),
            ],
            body: _index == 0
                ? const LibraryScreen()
                : Center(child: Text(l10n.settingsLabel)),
          );
        },
      ),
    );
  }
}
