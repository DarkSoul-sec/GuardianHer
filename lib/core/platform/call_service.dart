import '../result/result.dart';

/// Abstraction over phone call intents.
///
/// Android does not allow arbitrary apps to programmatically place emergency
/// calls and restricts `CALL_PHONE`, so the implementation opens the system
/// dialer pre-filled with the number and lets the user place the call.
abstract interface class CallService {
  /// Opens the system dialer pre-filled with [phoneNumber].
  Future<Result<void>> openDialer(String phoneNumber);
}