import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'privacy_controller.dart';

/// Tracks whether a destructive data deletion is in progress.
final privacyControllerProvider =
    NotifierProvider<PrivacyController, bool>(PrivacyController.new);