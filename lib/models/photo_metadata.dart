class PhotoMetadata {
  final int? width;
  final int? height;
  final DateTime? dateTaken;
  final String? cameraMake;
  final String? cameraModel;
  final String? iso;
  final String? aperture;
  final String? shutterSpeed;
  final String? focalLength;
  final double? gpsLatitude;
  final double? gpsLongitude;

  const PhotoMetadata({
    this.width,
    this.height,
    this.dateTaken,
    this.cameraMake,
    this.cameraModel,
    this.iso,
    this.aperture,
    this.shutterSpeed,
    this.focalLength,
    this.gpsLatitude,
    this.gpsLongitude,
  });

  String get dimensionsLabel {
    if (width == null || height == null) return 'Unknown';
    return '$width × $height';
  }
}