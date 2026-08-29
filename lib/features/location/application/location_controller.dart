import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failures.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/platform/location_service.dart';
import '../../../core/providers.dart';
import '../../../core/result/result.dart';
import '../../contacts/domain/trusted_contact.dart';
import '../domain/location_failures.dart';
import 'location_providers.dart';
import 'location_state.dart';

/// Drives the one-shot current-location flow.
///
/// Widgets never touch the location or permission services directly; they call
/// [captureLocation], [openInMaps] and [shareLocation] on this controller and
/// render [LocationState].
///
/// The flow is fail-open for emergencies: a location failure never cancels an
/// active SOS and never blocks the UI. Duplicate simultaneous requests are
/// prevented by the loading guard, and [reset] always takes effect — even while
/// loading — by invalidating any in-flight capture, so a stale result can never
/// resurrect an SOS that already ended.
class LocationController extends Notifier<LocationState> {
  LocationService get _service => ref.read(locationServiceProvider);
  PermissionService get _permissions => ref.read(permissionServiceProvider);

  /// Generation counter. [reset] bumps it to discard any in-flight capture.
  int _captureEpoch = 0;

  @override
  LocationState build() => const LocationState();

  /// Full manual capture flow used by the Location screen and SOS activation:
  ///
  /// services on → permission (request if retryable) → one-shot fix.
  Future<void> captureLocation() async {
    if (state.status == LocationStatus.loading) {
      return;
    }
    final epoch = ++_captureEpoch;
    state = const LocationState(status: LocationStatus.loading);

    final enabled = await _service.isLocationServiceEnabled();
    if (!_isCurrent(epoch)) return;
    if (!enabled) {
      state = const LocationState(
        status: LocationStatus.servicesDisabled,
        message: 'Location services are turned off.',
        openLocationSettings: true,
      );
      return;
    }

    var permission = await _service.checkPermission();
    if (!_isCurrent(epoch)) return;
    if (permission == PermissionStatus.denied) {
      permission = await _service.requestPermission();
      if (!_isCurrent(epoch)) return;
    }
    if (permission == PermissionStatus.permanentlyDenied) {
      state = const LocationState(
        status: LocationStatus.denied,
        message: 'Location permission is off. Open Settings to allow it.',
        openSettings: true,
      );
      return;
    }
    if (permission != PermissionStatus.granted) {
      state = const LocationState(
        status: LocationStatus.denied,
        message: 'Location permission was not granted.',
        canRetry: true,
      );
      return;
    }

    final result = await _service.getCurrentLocation();
    if (!_isCurrent(epoch)) return;
    switch (result) {
      case Ok(:final value):
        state = LocationState(status: LocationStatus.captured, point: value);
      case Err(:final failure):
        state = LocationState(
          status: failure is LocationTimeoutFailure
              ? LocationStatus.timeout
              : LocationStatus.unavailable,
          message: failure.message,
          canRetry: true,
          openLocationSettings: failure is LocationServicesDisabledFailure,
        );
    }
  }

  bool _isCurrent(int epoch) => epoch == _captureEpoch;

  /// Opens the system settings screen for this app.
  Future<void> openSettings() => _permissions.openSettings();

  /// Opens the device's location settings (where the GPS switch lives), then
  /// automatically resumes the capture when the user returns — so enabling
  /// location is a single switch, not a manual round trip through Settings.
  Future<void> openLocationSettings() async {
    final epoch = _captureEpoch;
    final opened = await _service.openLocationSettings();
    if (!opened || !_isCurrent(epoch)) {
      return;
    }
    await captureLocation();
  }

  /// Opens the captured location in the default map application.
  Future<Result<void>> openInMaps() async {
    final point = state.point;
    if (point == null) {
      return const Err(LocationUnavailableFailure());
    }
    return ref.read(mapServiceProvider).openLocation(point);
  }

  /// Composes a message with the captured location for the user to send.
  ///
  /// Always user-initiated: nothing is sent automatically. Opens the system
  /// SMS composer pre-filled with the location message; when no SMS app is
  /// installed (Wi-Fi-only device), falls back to the system share sheet so
  /// any messaging app can take it.
  Future<Result<void>> shareLocation() async {
    final point = state.point;
    if (point == null) {
      return const Err(LocationUnavailableFailure());
    }
    final message = ref.read(locationShareMessageProvider)(point);
    switch (await ref.read(smsServiceProvider).openComposer(
          phoneNumber: '',
          body: message,
        )) {
      case Ok():
        return const Ok(null);
      case Err(:final failure):
        if (failure is! NoSmsAppAvailableFailure) {
          return Err(failure);
        }
        return ref.read(shareServiceProvider).shareText(message);
    }
  }

  /// Opens a WhatsApp chat with [contact], pre-filled with the captured
  /// location message. Single, deliberate user action — one launch per call,
  /// never an automatic retry loop over multiple contacts.
  ///
  /// The service layer canonicalizes the stored digits-only number into the
  /// international form WhatsApp requires. The returned failure only ever
  /// means "the chat could not be opened" (app missing, invalid number,
  /// platform error); whether the recipient is registered on WhatsApp cannot
  /// be known here and is never claimed either way.
  Future<Result<void>> shareViaWhatsApp(TrustedContact contact) async {
    final point = state.point;
    if (point == null) {
      return const Err(LocationUnavailableFailure());
    }
    final message = ref.read(locationShareMessageProvider)(point);
    return ref.read(whatsappServiceProvider).openChat(
          phoneNumber: contact.phoneNumber,
          body: message,
        );
  }

  /// Returns to idle (e.g. after an SOS session ends).
  ///
  /// Always effective, even while a capture is loading: bumping the epoch
  /// discards the in-flight result so it cannot overwrite the reset state.
  void reset() {
    _captureEpoch++;
    state = const LocationState();
  }
}