import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/models/saved_signature.dart';
import 'package:folio/features/viewer/signature_providers.dart';
import 'package:folio/features/viewer/widgets/signature_capture_canvas.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Pick a signature to place, or manage the saved ones.
///
/// Management lives here rather than in Settings: creating your first
/// signature should not mean leaving the document you are trying to sign.
class SignatureSheet extends ConsumerWidget {
  const SignatureSheet({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final labelController = TextEditingController(text: l10n.signLabel);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.signAdd),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: InputDecoration(
                  labelText: l10n.signLabel,
                  hintText: l10n.signLabelHint,
                ),
              ),
              const SizedBox(height: 12),
              SignatureCaptureCanvas(
                onSaved: (strokes, aspectRatio) async {
                  await ref
                      .read(signatureRepositoryProvider)
                      .add(
                        label: labelController.text.trim().isEmpty
                            ? l10n.signLabel
                            : labelController.text.trim(),
                        strokes: strokes,
                        aspectRatio: aspectRatio,
                      );
                  ref.invalidate(signaturesProvider);
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    SavedSignature signature,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: signature.label);

    final newLabel = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.signRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.signLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l10n.signRename),
          ),
        ],
      ),
    );

    if (newLabel == null || newLabel.isEmpty) return;
    await ref.read(signatureRepositoryProvider).rename(signature.id, newLabel);
    ref.invalidate(signaturesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final signatures = ref.watch(signaturesProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.signChoose,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _add(context, ref),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.signAdd),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: signatures.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
                error: (_, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l10n.signNone),
                ),
                data: (list) => list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(l10n.signNone),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final s = list[i];
                          return ListTile(
                            // Painted from its own strokes, so there is no
                            // thumbnail file to keep in sync with the data.
                            leading: SizedBox(
                              width: 64,
                              height: 32,
                              child: CustomPaint(
                                painter: SignaturePreviewPainter(
                                  strokes: s.strokes,
                                  ink: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                            title: Text(s.label),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'rename') {
                                  await _rename(context, ref, s);
                                } else {
                                  await ref
                                      .read(signatureRepositoryProvider)
                                      .delete(s.id);
                                  ref.invalidate(signaturesProvider);
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text(l10n.signRename),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(l10n.signDelete),
                                ),
                              ],
                            ),
                            onTap: () {
                              ref.read(signingProvider.notifier).select(s);
                              Navigator.of(context).pop(true);
                            },
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
