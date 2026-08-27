import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/core/theme/app_theme.dart';
import 'package:folio/features/home/library_screen.dart';
import 'package:folio/features/viewer/viewer_screen.dart';
import 'package:folio/features/settings/settings_providers.dart';
import 'package:folio/features/settings/settings_screen.dart';
import 'package:folio/l10n/app_localizations.dart';
import 'package:folio/widgets/adaptive_scaffold.dart';

class FolioApp extends ConsumerStatefulWidget {
  const FolioApp({super.key});

  @override
  ConsumerState<FolioApp> createState() => _FolioAppState();
}

class _FolioAppState extends ConsumerState<FolioApp> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Follows the user's choice, which defaults to the system setting.
      themeMode: ref.watch(themeModeProvider).value ?? ThemeMode.system,
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
                ? LibraryScreen(
                    onOpenDocument: (doc) => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ViewerScreen(document: doc),
                      ),
                    ),
                  )
                : const SettingsScreen(),
          );
        },
      ),
    );
  }
}
