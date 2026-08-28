import 'package:flutter/services.dart';
import 'package:folio/domain/fonts/truetype_font.dart';

/// Loads the font Folio embeds.
///
/// Parsing builds a map of every character the font covers, which for Noto is
/// tens of thousands of entries. Doing that once and keeping it is the
/// difference between numbering a document instantly and visibly pausing.
class FontAssets {
  FontAssets({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const notoSans = 'assets/fonts/NotoSans-Regular.ttf';

  final AssetBundle _bundle;
  Future<TrueTypeFont>? _loading;

  /// The text face, parsed once and kept.
  ///
  /// The future is cached rather than the result, so two callers arriving
  /// together share one parse instead of racing to do it twice.
  Future<TrueTypeFont> text() => _loading ??= _parse();

  Future<TrueTypeFont> _parse() async {
    final data = await _bundle.load(notoSans);
    return TrueTypeFont.parse(data.buffer.asUint8List());
  }
}
