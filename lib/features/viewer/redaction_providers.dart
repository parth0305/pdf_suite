import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/redaction/redaction_box.dart';
import 'package:folio/domain/repositories/redaction_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final redactionRepositoryProvider = Provider<RedactionRepository>(
  (ref) => throw UnimplementedError(
    'redactionRepositoryProvider must be overridden',
  ),
);

/// Boxes the user has drawn but not yet applied.
///
/// Pending, deliberately: redaction is irreversible in its output, so nothing
/// is written until the confirmation is accepted.
class RedactionSession extends Notifier<List<RedactionBox>> {
  @override
  List<RedactionBox> build() => const [];

  void add(RedactionBox box) => state = [...state, box];

  void removeAt(int index) => state = [
    for (var i = 0; i < state.length; i++)
      if (i != index) state[i],
  ];

  void replaceAt(int index, RedactionBox box) => state = [
    for (var i = 0; i < state.length; i++)
      if (i == index) box else state[i],
  ];

  void clear() => state = const [];

  List<RedactionBox> onPage(int pageIndex) =>
      state.where((b) => b.pageIndex == pageIndex).toList();
}

final redactionSessionProvider =
    NotifierProvider<RedactionSession, List<RedactionBox>>(
      RedactionSession.new,
    );
