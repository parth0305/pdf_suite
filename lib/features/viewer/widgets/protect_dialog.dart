import 'package:flutter/material.dart';
import 'package:folio/domain/models/protect_request.dart';
import 'package:folio/domain/pdf/pdf_permissions.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Collects a password twice, plus optional restrictions, returning them only
/// when both password entries match.
///
/// Nothing here is logged: a password is the most sensitive value the app
/// handles, and a document protected with a typo is unrecoverable.
Future<ProtectRequest?> showProtectDialog(BuildContext context) {
  final first = TextEditingController();
  final second = TextEditingController();
  final owner = TextEditingController();

  var printing = true;
  var copying = true;
  var modifying = true;
  var annotating = true;
  var showRestrictions = false;

  return showDialog<ProtectRequest>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;

      return StatefulBuilder(
        builder: (context, setState) {
          final password = first.text;
          final matches = password.isNotEmpty && password == second.text;

          Widget allow(String label, bool value, ValueChanged<bool> onChanged) {
            return CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: value,
              title: Text(label),
              onChanged: (v) => setState(() => onChanged(v ?? true)),
            );
          }

          return AlertDialog(
            title: Text(l10n.protectMode),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: first,
                    autofocus: true,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: l10n.protectPassword,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: second,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: l10n.protectConfirm,
                      errorText: second.text.isNotEmpty && !matches
                          ? l10n.protectMismatch
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.protectWarning,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  // Restrictions stay folded away: most people protecting a
                  // document want it unreadable, not partly readable.
                  ExpansionTile(
                    key: const Key('protect-restrictions'),
                    tilePadding: EdgeInsets.zero,
                    initiallyExpanded: showRestrictions,
                    onExpansionChanged: (v) =>
                        setState(() => showRestrictions = v),
                    title: Text(l10n.protectPermissionsTitle),
                    children: [
                      allow(
                        l10n.protectAllowPrinting,
                        printing,
                        (v) => printing = v,
                      ),
                      allow(
                        l10n.protectAllowCopying,
                        copying,
                        (v) => copying = v,
                      ),
                      allow(
                        l10n.protectAllowModifying,
                        modifying,
                        (v) => modifying = v,
                      ),
                      allow(
                        l10n.protectAllowAnnotating,
                        annotating,
                        (v) => annotating = v,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: owner,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: l10n.protectOwnerPassword,
                          helperText: l10n.protectOwnerHint,
                          helperMaxLines: 3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.protectAdvisory,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.cancelAction),
              ),
              FilledButton(
                onPressed: matches
                    ? () => Navigator.of(dialogContext).pop(
                        ProtectRequest(
                          userPassword: password,
                          ownerPassword: owner.text,
                          permissions: PdfPermissions(
                            printing: printing,
                            copying: copying,
                            modifying: modifying,
                            annotating: annotating,
                          ),
                        ),
                      )
                    : null,
                child: Text(l10n.protectApply),
              ),
            ],
          );
        },
      );
    },
  );
}
