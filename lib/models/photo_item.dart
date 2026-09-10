class PhotoItem {
  final String path;
  final String name;
  final String album;
  final int sizeBytes;
  final DateTime modifiedAt;
  final DateTime? dateTaken;
  final bool isVideo;
  bool isFavorite;
  double aspectRatio;

  PhotoItem({
    required this.path,
    required this.name,
    required this.album,
    required this.sizeBytes,
    required this.modifiedAt,
    this.dateTaken,
    required this.isVideo,
    this.isFavorite = false,
    this.aspectRatio = 1.0,
  });

  String get id => path;

  String get extension => path.contains('.')
      ? path.substring(path.lastIndexOf('.'))
      : '';

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Map<String, dynamic> toMap() => {
        'path': path,
        'name': name,
        'album': album,
        'sizeBytes': sizeBytes,
        'modifiedAt': modifiedAt.millisecondsSinceEpoch,
        'dateTaken': dateTaken?.millisecondsSinceEpoch,
        'isVideo': isVideo ? 1 : 0,
        'isFavorite': isFavorite ? 1 : 0,
      };

  factory PhotoItem.fromMap(Map<String, dynamic> map) {
    final dtRaw = map['dateTaken'];
    DateTime? dt;
    if (dtRaw is int && dtRaw > 0) {
      dt = DateTime.fromMillisecondsSinceEpoch(dtRaw);
    }
    return PhotoItem(
      path: map['path'] as String,
      name: map['name'] as String,
      album: map['album'] as String,
      sizeBytes: map['sizeBytes'] as int,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(map['modifiedAt'] as int),
      dateTaken: dt,
      isVideo: (map['isVideo'] as int) == 1,
      isFavorite: (map['isFavorite'] as int) == 1,
    );
  }
}

class Album {
  final String name;
  final String path;
  final String coverPath;
  final int photoCount;

  Album({
    required this.name,
    required this.path,
    required this.coverPath,
    required this.photoCount,
  });
}

enum SortField { name, dateModified, dateTaken, size }

enum SortOrder { ascending, descending }

class SortMode {
  SortField field;
  SortOrder order;

  SortMode({this.field = SortField.dateModified, this.order = SortOrder.descending});

  String get label {
    final fieldName = switch (field) {
      SortField.name => 'Name',
      SortField.dateModified => 'Date modified',
      SortField.dateTaken => 'Date taken',
      SortField.size => 'Size',
    };
    final orderName = order == SortOrder.ascending ? '↑' : '↓';
    return '$fieldName $orderName';
  }
}