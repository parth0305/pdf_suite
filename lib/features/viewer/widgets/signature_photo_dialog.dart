import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/data/signature/signature_photo_source.dart';
import 'package:folio/features/scanner/scanner_providers.dart';
import 'package:folio/features/viewer/signature_providers.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Photographs a signature, shows the extracted ink, and saves it.
///
/// The preview is the point. Background removal on a photograph is a judgement
/// the algorithm can get wrong, and the person whose signature it is can tell
/// at a glance far better than any threshold can.
Future<bool> showSignaturePhotoDialog(BuildContext context) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => const _SignaturePhotoDialog(),
  );
  return saved ?? false;
}

class _SignaturePhotoDialog extends ConsumerStatefulWidget {
  const _SignaturePhotoDialog();

  @override
  ConsumerState<_SignaturePhotoDialog> createState() =>
      _SignaturePhotoDialogState();
}

class _SignaturePhotoDialogState extends ConsumerState<_SignaturePhotoDialog> {
  final _label = TextEditingController(text: 'Signature');
  SignaturePhoto? _photo;
  _SignaturePreview? _preview;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool fromCamera}) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final photo = await SignaturePhotoSource(
        ref.read(scanImageSourceProvider),
      ).capture(fromCamera: fromCamera);

      if (photo == null || !mounted) return;

      // A photograph too dark to separate would otherwise become a black
      // rectangle on someone's contract.
      if (!photo.isUsable) {
        setState(() => _error = l10n.signPhotoUnusable);
        return;
      }

      final preview = await _SignaturePreview.from(photo);
      if (!mounted) return;
      setState(() {
        _photo = photo;
        _preview = preview;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final photo = _photo;
    if (photo == null) return;

    await ref
        .read(signatureRepositoryProvider)
        .addPhoto(
          label: _label.text.trim().isEmpty ? 'Signature' : _label.text.trim(),
          rgba: photo.rgba,
          pixelWidth: photo.width,
          pixelHeight: photo.height,
        );

    ref.invalidate(signaturesProvider);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.signAddPhoto),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.signPhotoHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_preview != null) ...[
              // A chequerboard would be better still, but the surface colour
              // already shows through anywhere the paper was removed.
              Container(
                height: 120,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(8),
                child: Image.memory(_preview!.png, fit: BoxFit.contain),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _label,
                decoration: InputDecoration(labelText: l10n.signPhotoLabel),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(fromCamera: true),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(l10n.signPhotoCamera),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(fromCamera: false),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(l10n.signPhotoGallery),
                  ),
                ),
              ],
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
          onPressed: _photo == null || _busy ? null : _save,
          child: Text(l10n.signAdd),
        ),
      ],
    );
  }
}

/// A PNG of the extracted ink, for the preview.
class _SignaturePreview {
  const _SignaturePreview(this.png);

  final Uint8List png;

  static Future<_SignaturePreview> from(SignaturePhoto photo) async =>
      _SignaturePreview(
        await encodeRgbaToPng(photo.rgba, photo.width, photo.height),
      );
}
