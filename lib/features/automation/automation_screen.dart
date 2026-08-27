import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/automation/automation_rule.dart';
import 'package:folio/features/automation/automation_providers.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Lists the rules that run when a document is added, and lets them be added,
/// switched off, or removed.
class AutomationScreen extends ConsumerWidget {
  const AutomationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final rules = ref.watch(automationRulesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.automationTitle)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l10n.automationAdd),
        onPressed: () async {
          final created = await showDialog<bool>(
            context: context,
            builder: (_) => const _AddRuleDialog(),
          );
          if (created == true) ref.invalidate(automationRulesProvider);
        },
      ),
      body: Column(
        children: [
          // Both notes explain a decision the user would otherwise discover by
          // surprise: why a watermark rule leaves two documents, and why
          // protect is missing entirely.
          _Note(text: l10n.automationInPlace),
          _Note(text: l10n.automationNoProtect, warning: true),
          Expanded(
            child: rules.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (list) => list.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.automationEmpty,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) => _RuleTile(rule: list[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.warning = false});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: warning ? scheme.errorContainer : scheme.secondaryContainer,
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: warning
              ? scheme.onErrorContainer
              : scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _RuleTile extends ConsumerWidget {
  const _RuleTile({required this.rule});

  final AutomationRule rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    final conditions = [
      if (rule.nameContains?.trim().isNotEmpty ?? false)
        '"${rule.nameContains!.trim()}"',
      if (rule.minSizeBytes != null)
        '≥ ${(rule.minSizeBytes! / 1024).round()} KB',
    ];

    return SwitchListTile(
      value: rule.enabled,
      title: Text(switch (rule.action) {
        AutomationAction.compress => l10n.automationRuleCompress,
        AutomationAction.ocr => l10n.automationRuleOcr,
        AutomationAction.watermark => l10n.automationRuleWatermark,
      }),
      subtitle: Text(
        [l10n.automationWhen, ...conditions].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      secondary: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: l10n.automationDelete,
        onPressed: () async {
          await ref.read(automationRepositoryProvider).remove(rule.id);
          ref.invalidate(automationRulesProvider);
        },
      ),
      onChanged: (value) async {
        await ref
            .read(automationRepositoryProvider)
            .setEnabled(rule.id, enabled: value);
        ref.invalidate(automationRulesProvider);
      },
    );
  }
}

class _AddRuleDialog extends ConsumerStatefulWidget {
  const _AddRuleDialog();

  @override
  ConsumerState<_AddRuleDialog> createState() => _AddRuleDialogState();
}

class _AddRuleDialogState extends ConsumerState<_AddRuleDialog> {
  AutomationAction _action = AutomationAction.compress;
  final _name = TextEditingController();
  final _size = TextEditingController();
  final _watermark = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final needsText = _action == AutomationAction.watermark;
    // A watermark rule with no text would throw on a document the user was
    // never asked about, so it cannot be created at all.
    final canSave = !needsText || _watermark.text.trim().isNotEmpty;

    return AlertDialog(
      title: Text(l10n.automationAdd),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.automationWhen),
            const SizedBox(height: 8),
            DropdownButtonFormField<AutomationAction>(
              initialValue: _action,
              items: [
                DropdownMenuItem(
                  value: AutomationAction.compress,
                  child: Text(l10n.automationRuleCompress),
                ),
                DropdownMenuItem(
                  value: AutomationAction.ocr,
                  child: Text(l10n.automationRuleOcr),
                ),
                DropdownMenuItem(
                  value: AutomationAction.watermark,
                  child: Text(l10n.automationRuleWatermark),
                ),
              ],
              onChanged: (v) => setState(() => _action = v ?? _action),
            ),
            if (needsText) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _watermark,
                decoration: InputDecoration(
                  labelText: l10n.automationWatermarkText,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: l10n.automationNameContains,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _size,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l10n.automationMinSize),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: canSave
              ? () async {
                  final kb = int.tryParse(_size.text.trim());

                  await ref
                      .read(automationRepositoryProvider)
                      .add(
                        action: _action,
                        nameContains: _name.text.trim().isEmpty
                            ? null
                            : _name.text.trim(),
                        minSizeBytes: kb == null ? null : kb * 1024,
                        watermarkText: needsText
                            ? _watermark.text.trim()
                            : null,
                      );
                  if (context.mounted) Navigator.of(context).pop(true);
                }
              : null,
          child: Text(l10n.automationAdd),
        ),
      ],
    );
  }
}
