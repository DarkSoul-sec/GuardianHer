import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/secure_storage_app_lock_repository.dart';
import '../domain/app_lock_repository.dart';
import '../domain/credential_policy.dart';
import 'app_lock_controller.dart';
import 'app_lock_state.dart';
import 'pin_hasher.dart';

/// Validation policy for stored PIN credentials.
final credentialPolicyProvider = Provider<CredentialPolicy>(
  (ref) => const CredentialPolicy(),
);

/// Binds the app-lock repository to secure storage.
final appLockRepositoryProvider = Provider<AppLockRepository>(
  (ref) => SecureStorageAppLockRepository(
    storage: ref.watch(secureStorageServiceProvider),
    policy: ref.watch(credentialPolicyProvider),
  ),
);

/// PIN derivation/verification. Tests override this with a low-iteration
/// instance to keep hashing fast; stored iteration counts are always honored.
final pinHasherProvider = Provider<PinHasher>((ref) => const PinHasher());

/// The application lock controller.
final appLockControllerProvider =
    NotifierProvider<AppLockController, AppLockState>(AppLockController.new);