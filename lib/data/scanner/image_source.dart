import 'dart:io';

import 'package:image_picker/image_picker.dart' as picker;

/// Where a scanned page's pixels come from.
///
/// An interface, not a direct call to `image_picker`, so the scanner's own
/// logic can be tested with bytes from a fixture. A camera and a gallery exist
/// only on a real device; without this boundary the whole feature would be
/// verifiable by hand alone.
abstract interface class ScanImageSource {
  /// One photograph, or null when the user backed out.
  Future<List<int>?> capture();

  /// Any number of existing images.
  Future<List<List<int>>> pickFromGallery();
}

/// Longest edge, in pixels, requested from the platform.
///
/// Enough for a readable A4 page at roughly 170 DPI. It is also what forces
/// the platform to re-encode, which is what bakes EXIF orientation into the
/// pixels - PDF ignores EXIF, so a raw camera JPEG would embed sideways.
const double kScanMaxWidth = 2000;

/// JPEG quality requested from the platform. Also forces the re-encode.
const int kScanQuality = 85;

class PlatformImageSource implements ScanImageSource {
  PlatformImageSource({picker.ImagePicker? impl})
    : _picker = impl ?? picker.ImagePicker();

  final picker.ImagePicker _picker;

  @override
  Future<List<int>?> capture() async {
    final shot = await _picker.pickImage(
      source: picker.ImageSource.camera,
      maxWidth: kScanMaxWidth,
      imageQuality: kScanQuality,
    );

    return shot == null ? null : File(shot.path).readAsBytes();
  }

  @override
  Future<List<List<int>>> pickFromGallery() async {
    final shots = await _picker.pickMultiImage(
      maxWidth: kScanMaxWidth,
      imageQuality: kScanQuality,
    );

    return [for (final s in shots) await File(s.path).readAsBytes()];
  }
}
