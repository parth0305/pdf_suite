import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/models/saved_signature.dart';
import 'package:folio/domain/repositories/signature_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final signatureRepositoryProvider = Provider<SignatureRepository>(
  (ref) => throw UnimplementedError(
    'signatureRepositoryProvider must be overridden',
  ),
);

final signaturesProvider = FutureProvider<List<SavedSignature>>(
  (ref) => ref.watch(signatureRepositoryProvider).all(),
);

class SigningState {
  const SigningState({this.chosen});

  /// The signature about to be placed, if any.
  final SavedSignature? chosen;
}

final signingProvider = NotifierProvider<SigningController, SigningState>(
  SigningController.new,
);

class SigningController extends Notifier<SigningState> {
  @override
  SigningState build() => const SigningState();

  void select(SavedSignature? signature) =>
      state = SigningState(chosen: signature);
}
