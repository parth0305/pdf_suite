import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/data/scanner/image_source.dart';
import 'package:folio/domain/repositories/scanner_repository.dart';
import 'package:folio/domain/scanner/scanned_page.dart';

/// Overridden at app start; reading either unoverridden is a programming error.
final scannerRepositoryProvider = Provider<ScannerRepository>(
  (ref) =>
      throw UnimplementedError('scannerRepositoryProvider must be overridden'),
);

final scanImageSourceProvider = Provider<ScanImageSource>(
  (ref) =>
      throw UnimplementedError('scanImageSourceProvider must be overridden'),
);

/// Pages captured but not yet saved.
class ScanSession extends Notifier<List<ScannedPage>> {
  @override
  List<ScannedPage> build() => const [];

  void add(ScannedPage page) => state = [...state, page];

  void addAll(Iterable<ScannedPage> pages) => state = [...state, ...pages];

  void removeAt(int index) => state = [
    for (var i = 0; i < state.length; i++)
      if (i != index) state[i],
  ];

  /// Moves the page at [from] to [to], which is what a reorder drag does.
  ///
  /// No special case for `from == to`: removing at an index and re-inserting
  /// at the same one gives back the same list. A guard was tried here and no
  /// mutation could distinguish it, which is the definition of dead code.
  void move(int from, int to) {
    final next = [...state];
    final page = next.removeAt(from);
    next.insert(to, page);
    state = next;
  }

  void clear() => state = const [];
}

final scanSessionProvider = NotifierProvider<ScanSession, List<ScannedPage>>(
  ScanSession.new,
);
