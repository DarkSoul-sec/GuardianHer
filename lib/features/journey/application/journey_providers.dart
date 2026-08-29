import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'journey_controller.dart';
import '../domain/journey_state.dart';

final journeyControllerProvider =
    NotifierProvider<JourneyController, JourneyState>(
  JourneyController.new,
);
