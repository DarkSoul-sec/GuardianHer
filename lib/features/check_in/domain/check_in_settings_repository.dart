import '../../../core/result/result.dart';
import 'check_in_settings.dart';

/// Loads and persists [CheckInSettings].
///
/// The implementation owns the storage keys and JSON codec. Reads never throw:
/// corrupt or missing data resolves to [CheckInSettings.initial] so the
/// feature degrades to the safe default (disabled).
abstract interface class CheckInSettingsRepository {
  Future<Result<CheckInSettings>> load();

  Future<Result<void>> save(CheckInSettings settings);
}