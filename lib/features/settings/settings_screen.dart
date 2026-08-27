import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/features/automation/automation_screen.dart';
import 'package:folio/features/settings/settings_providers.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Appearance, workflow and about.
///
/// This tab was an empty placeholder that displayed the word "Settings" and
/// nothing else. Automation lived behind an icon in the library toolbar, where
/// nobody would look for it, and the theme was hardcoded to follow the system
/// with no way to override it.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.version = '1.0.0'});

  final String version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ref.watch(themeModeProvider);

    return ListView(
      children: [
        _Heading(l10n.settingsAppearance),
        // RadioGroup rather than per-tile groupValue: the older API is
        // deprecated and the analyzer runs with --fatal-infos.
        RadioGroup<ThemeMode>(
          groupValue: theme.value ?? ThemeMode.system,
          onChanged: (value) => value == null
              ? null
              : ref.read(themeModeProvider.notifier).set(value),
          child: Column(
            children: [
              for (final mode in ThemeMode.values)
                RadioListTile<ThemeMode>(
                  value: mode,
                  title: Text(switch (mode) {
                    ThemeMode.system => l10n.settingsThemeSystem,
                    ThemeMode.light => l10n.settingsThemeLight,
                    ThemeMode.dark => l10n.settingsThemeDark,
                  }),
                ),
            ],
          ),
        ),
        const Divider(),

        _Heading(l10n.settingsWorkflow),
        ListTile(
          leading: const Icon(Icons.auto_awesome_motion_outlined),
          title: Text(l10n.automationTitle),
          subtitle: Text(l10n.settingsAutomationSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AutomationScreen()),
          ),
        ),
        const Divider(),

        _Heading(l10n.settingsAbout),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.settingsVersion),
          subtitle: Text(version),
        ),
        // The claim in PRIVACY.md, where someone using the app can actually
        // read it. A privacy promise only in a repository is a promise made to
        // developers.
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: Text(l10n.settingsPrivacy),
          subtitle: Text(l10n.settingsPrivacyBody),
          isThreeLine: true,
        ),
        ListTile(
          leading: const Icon(Icons.balance_outlined),
          title: Text(l10n.settingsLicenses),
          subtitle: Text(l10n.settingsLicensesSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(
            context: context,
            applicationName: l10n.appTitle,
            applicationVersion: version,
          ),
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}
