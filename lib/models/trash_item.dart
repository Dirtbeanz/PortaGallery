class TrashItem {
  final String trashedPath;
  final String originalPath;
  final DateTime deletedAt;

  const TrashItem({
    required this.trashedPath,
    required this.originalPath,
    required this.deletedAt,
  });

  String get name {
    final index = originalPath.lastIndexOf('/');
    return index < 0 ? originalPath : originalPath.substring(index + 1);
  }

  factory TrashItem.fromMap(Map<String, dynamic> map) {
    return TrashItem(
      trashedPath: map['trashed_path'] as String,
      originalPath: map['original_path'] as String,
      deletedAt:
          DateTime.fromMillisecondsSinceEpoch(map['deleted_at'] as int),
    );
  }
}
