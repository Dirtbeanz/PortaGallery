class PhotoNotes {
  final List<String> tags;
  final String comment;

  const PhotoNotes({this.tags = const [], this.comment = ''});

  PhotoNotes copyWith({List<String>? tags, String? comment}) {
    return PhotoNotes(
      tags: tags ?? this.tags,
      comment: comment ?? this.comment,
    );
  }

  bool get isEmpty => tags.isEmpty && comment.trim().isEmpty;

  Map<String, dynamic> toMap() => {
        'tags': tags.join(','),
        'comment': comment,
      };

  factory PhotoNotes.fromMap(Map<String, dynamic> map) {
    final raw = (map['tags'] as String? ?? '').trim();
    return PhotoNotes(
      tags: raw.isEmpty ? [] : raw.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
      comment: (map['comment'] as String? ?? '').trim(),
    );
  }
}