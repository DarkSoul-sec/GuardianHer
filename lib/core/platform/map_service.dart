import '../../features/location/domain/location_point.dart';
import '../result/result.dart';

/// Abstraction over opening locations in map applications.
abstract interface class MapService {
  /// Opens the default map application at [point].
  ///
  /// Reports success only when the platform actually launched a map app or
  /// browser. No Google Maps API key is required.
  Future<Result<void>> openLocation(LocationPoint point);
}
