/// A virtual folder. Managed files are stored content-addressed and flat, so a
/// collection is a grouping in the database rather than a directory on disk.
class LibraryCollection {
  const LibraryCollection({required this.id, required this.name});

  final int id;
  final String name;
}
