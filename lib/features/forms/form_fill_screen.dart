import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/core/errors/failure_messages.dart';
import 'package:folio/core/theme/app_theme.dart';
import 'package:folio/domain/forms/form_field.dart' as forms;
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/features/home/providers.dart';
import 'package:folio/features/viewer/form_providers.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Fills in a document's form.
///
/// A full screen rather than a sheet: a real form runs to dozens of fields,
/// and a sheet that scrolls behind the keyboard is where filling one stops
/// being possible.
class FormFillScreen extends ConsumerStatefulWidget {
  const FormFillScreen({required this.document, super.key});

  final LibraryDocument document;

  @override
  ConsumerState<FormFillScreen> createState() => _FormFillScreenState();
}

class _FormFillScreenState extends ConsumerState<FormFillScreen> {
  final _values = <String, String?>{};
  final _controllers = <String, TextEditingController>{};

  List<forms.FormField>? _fields;
  AppFailure? _failure;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final fields = await ref
          .read(formRepositoryProvider)
          .fields(widget.document.id);
      if (!mounted) return;

      setState(() {
        _fields = fields;
        for (final field in fields) {
          if (field.kind == forms.FormFieldKind.text) {
            _controllers[field.name] = TextEditingController(
              text: field.value ?? '',
            );
          }
        }
      });
    } on AppFailure catch (f) {
      if (mounted) setState(() => _failure = f);
    }
  }

  /// The value a field currently shows: what has been typed, or what the
  /// document already held.
  String? _valueOf(forms.FormField field) =>
      _values.containsKey(field.name) ? _values[field.name] : field.value;

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Typed text is only in its controller until now: reading the controllers
    // at save is what keeps a field the user never left from being dropped.
    for (final entry in _controllers.entries) {
      _values[entry.key] = entry.value.text;
    }

    setState(() => _saving = true);
    try {
      final out = await ref
          .read(formRepositoryProvider)
          .fill(widget.document.id, _values);
      await ref.read(libraryControllerProvider.notifier).refresh();
      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(content: Text(l10n.formSaved(out.displayName))),
      );
      navigator.pop();
    } on AppFailure catch (f) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(f, l10n).title)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fields = _fields;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.formMode),
        actions: [
          if (fields != null && fields.any((f) => f.isFillable))
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(l10n.formSave),
            ),
        ],
      ),
      body: switch ((fields, _failure)) {
        (_, final AppFailure f) => _Message(
          title: failureMessage(f, l10n).title,
          body: failureMessage(f, l10n).body,
        ),
        (null, _) => const Center(child: CircularProgressIndicator()),
        (final list, _) when list!.isEmpty => _Message(
          title: l10n.formEmptyTitle,
          body: l10n.formEmptyBody,
        ),
        (final list, _) => ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space * 2,
            vertical: AppTheme.space,
          ),
          children: [
            // Said once, at the top, rather than beside every field: a form
            // that recalculates a total will not recalculate it here, and
            // finding that out after signing is worse than reading it now.
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space * 2),
              child: Text(
                l10n.formNoScripts,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final field in list!)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.space * 2),
                child: _Field(
                  field: field,
                  controller: _controllers[field.name],
                  value: _valueOf(field),
                  onChanged: (v) => setState(() => _values[field.name] = v),
                ),
              ),
          ],
        ),
      },
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.field,
    required this.value,
    required this.onChanged,
    this.controller,
  });

  final forms.FormField field;
  final String? value;
  final TextEditingController? controller;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = field.isRequired ? '${field.name} *' : field.name;

    if (!field.isFillable) {
      // Shown rather than hidden. A read-only field is information the form is
      // trying to give; leaving it out loses it.
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Text(
          value?.isNotEmpty ?? false
              ? value!
              : field.kind == forms.FormFieldKind.signature
              ? l10n.formSignatureField
              : l10n.formReadOnly,
        ),
        enabled: false,
      );
    }

    return switch (field.kind) {
      forms.FormFieldKind.checkBox => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value != null && value != 'Off' && value!.isNotEmpty,
        onChanged: (on) =>
            onChanged(on ? (field.options.firstOrNull ?? 'Yes') : 'Off'),
      ),
      forms.FormFieldKind.radio => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          RadioGroup<String>(
            groupValue: value,
            onChanged: onChanged,
            child: Column(
              children: [
                for (final option in field.options)
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: option,
                    title: Text(option),
                  ),
              ],
            ),
          ),
        ],
      ),
      forms.FormFieldKind.choice => DropdownButtonFormField<String>(
        initialValue: field.exports.contains(value) ? value : null,
        decoration: InputDecoration(labelText: label),
        items: [
          for (var i = 0; i < field.options.length; i++)
            DropdownMenuItem(
              // Stored as the export value, shown as the label: the form's
              // owner reads `IN` where the person picked `India`.
              value: i < field.exports.length
                  ? field.exports[i]
                  : field.options[i],
              child: Text(field.options[i]),
            ),
        ],
        onChanged: onChanged,
      ),
      _ => TextField(
        controller: controller,
        obscureText: field.isPassword,
        maxLines: field.isMultiline ? 4 : 1,
        maxLength: field.maxLength,
        decoration: InputDecoration(labelText: label),
      ),
    };
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppTheme.space * 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: AppTheme.space * 2),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTheme.space),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    ),
  );
}
