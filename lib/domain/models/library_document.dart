import 'package:folio/domain/models/document_ref.dart';

class LibraryDocument {
  const LibraryDocument({
    required this.id,
    required this.ref,
    required this.displayName,
    required this.sizeBytes,
    required this.addedAt,
    required this.isFavorite,
    this.createdByFolio = false,
    this.lastOpenedAt,
    this.pageCount,
    this.collectionId,
  });

  final int id;
  final DocumentRef ref;
  final String displayName;
  final int sizeBytes;
  final DateTime addedAt;
  final DateTime? lastOpenedAt;
  final bool isFavorite;

  /// True when Folio produced this file, so it can be rewritten in place.
  final bool createdByFolio;
  final int? pageCount;

  /// Null means the document sits at the library root. Folders are virtual.
  final int? collectionId;

  bool get isManaged => ref is ManagedRef;

  LibraryDocument copyWith({
    DateTime? lastOpenedAt,
    bool? isFavorite,
    int? pageCount,
    String? displayName,
    int? collectionId,
    bool clearCollection = false,
  }) => LibraryDocument(
    id: id,
    ref: ref,
    createdByFolio: createdByFolio,
    displayName: displayName ?? this.displayName,
    sizeBytes: sizeBytes,
    addedAt: addedAt,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    isFavorite: isFavorite ?? this.isFavorite,
    pageCount: pageCount ?? this.pageCount,
    collectionId: clearCollection ? null : (collectionId ?? this.collectionId),
  );
}
