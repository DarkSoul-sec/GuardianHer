import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/location_point.dart';
import '../domain/location_share_message.dart';
import 'location_controller.dart';
import 'location_state.dart';

/// The current-location controller.
final locationControllerProvider =
    NotifierProvider<LocationController, LocationState>(LocationController.new);

/// Builds the share message for a captured location.
///
/// Centralized so the wording can be changed in one place. Sharing is always
/// user-initiated.
final locationShareMessageProvider =
    Provider<String Function(LocationPoint)>(
  (ref) => buildLocationShareMessage,
);