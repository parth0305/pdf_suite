import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:folio/data/scanner/image_source.dart';
import 'package:folio/domain/signature/background_removal.dart';

/// The result of turning a photograph into a usable signature.
class SignaturePhoto {
  const SignaturePhoto({
    required this.rgba,
    required this.width,
    required this.height,
    required this.extraction,
  });

  final List<int> rgba;
  final int width;
  final int height;
  final InkExtraction extraction;

  bool get isUsable => extraction.isUsable;
}

/// Picks a photograph of a signature and extracts the ink from it.
///
/// Decoding goes through `dart:ui`, which every Flutter app already has, so no
/// image package is needed. The picked JPEG is never stored: what is kept is
/// the extracted ink, because the photograph is a picture of someone's desk
/// and Folio has no business keeping it.
class SignaturePhotoSource {
  const SignaturePhotoSource(this._images);

  final ScanImageSource _images;

  /// Null when the user backed out of the picker.
  Future<SignaturePhoto?> capture({required bool fromCamera}) async {
    final picked = fromCamera
        ? await _images.capture()
        : (await _images.pickFromGallery()).firstOrNull;
    if (picked == null) return null;

    return extract(picked);
  }

  /// Exposed separately so the extraction can be exercised without a picker.
  static Future<SignaturePhoto> extract(List<int> encoded) async {
    final decoded = await _decode(Uint8List.fromList(encoded));
    final extraction = removeBackground(
      decoded.rgba,
      decoded.width,
      decoded.height,
    );

    return SignaturePhoto(
      rgba: extraction.rgba,
      width: decoded.width,
      height: decoded.height,
      extraction: extraction,
    );
  }

  static Future<({List<int> rgba, int width, int height})> _decode(
    Uint8List bytes,
  ) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    // Straight RGBA, not premultiplied: the extraction reads colour channels
    // directly, and premultiplied values would be darkened by their own alpha.
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final result = (
      rgba: data!.buffer.asUint8List().toList(),
      width: image.width,
      height: image.height,
    );

    image.dispose();
    codec.dispose();
    return result;
  }
}

/// Encodes RGBA as a PNG, for showing the extracted ink on screen.
///
/// PNG because it is the one format `dart:ui` can encode and the one that
/// keeps the alpha channel - a JPEG preview would show the paper back again as
/// black.
Future<Uint8List> encodeRgbaToPng(List<int> rgba, int width, int height) async {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List.fromList(rgba),
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );

  final image = await completer.future;
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();

  return data!.buffer.asUint8List();
}
