import '../result/result.dart';

/// A geographic coordinate in decimal degrees.
class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}

/// Abstraction over device GPS access.
///
/// Implementations are plugin-backed and injected in later phases; this
/// interface keeps presentation code decoupled from the platform channel.
abstract interface class LocationService {
  /// Returns the current device position.
  Future<Result<GeoPoint>> getCurrentLocation();
}