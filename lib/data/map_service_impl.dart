import 'package:url_launcher/url_launcher.dart';

import '../core/error/failures.dart';
import '../core/platform/map_service.dart';
import '../core/result/result.dart';
import '../features/location/domain/location_point.dart';

/// Builds the `geo:` URI that opens the default map application at [point].
///
/// Uses the RFC 5870 `geo:` scheme with a `q` query so the pin is placed
/// exactly at the coordinates. The comma stays literal (as most map apps
/// expect), so the query string is built by hand instead of relying on
/// `Uri(queryParameters:)`, which would percent-encode it. Requires no Google
/// Maps API key.
Uri buildGeoUri(LocationPoint point) {
  return Uri.parse(
    'geo:0,0?q=${point.latitude},${point.longitude}',
  );
}

/// Opens the default map application at a location.
///
/// Reports success only when the platform actually launched a map app or
/// browser; it never claims a map opened that did not. If no compatible app or
/// browser exists the action fails with [UnableToOpenMapsFailure].
class UrlLauncherMapService implements MapService {
  const UrlLauncherMapService();

  @override
  Future<Result<void>> openLocation(LocationPoint point) async {
    final uri = buildGeoUri(point);
    try {
      if (!await canLaunchUrl(uri)) {
        return const Err(UnableToOpenMapsFailure());
      }
      final launched = await launchUrl(uri);
      if (!launched) {
        return const Err(UnableToOpenMapsFailure());
      }
      return const Ok(null);
    } catch (_) {
      return const Err(UnableToOpenMapsFailure());
    }
  }
}