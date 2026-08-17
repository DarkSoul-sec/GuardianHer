import '../result/result.dart';
import 'location_service.dart';

/// Abstraction over opening locations in map applications.
abstract interface class MapService {
  /// Opens the default map application at [point].
  Future<Result<void>> openLocation(GeoPoint point);
}