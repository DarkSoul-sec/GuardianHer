import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/app_lock_providers.dart';
import '../../features/auth/domain/app_lock_status.dart';
import '../../features/auth/presentation/lock_screen.dart';
import '../../features/contacts/presentation/contacts_screen.dart';
import '../../features/emergency_history/presentation/emergency_history_screen.dart';
import '../../features/location/presentation/location_screen.dart';
import '../../features/permissions/presentation/permissions_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/settings/presentation/change_pin_screen.dart';
import '../../features/settings/presentation/privacy_policy_screen.dart';
import '../../features/settings/presentation/security_settings_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/sos/presentation/sos_screen.dart';
import '../../shared/widgets/app_shell.dart';
import '../home_screen.dart';

/// Central route path registry.
abstract final class AppRoutes {
  AppRoutes._();

  static const lock = '/lock';
  static const home = '/';
  static const profile = '/profile';
  static const contacts = '/contacts';
  static const sos = '/sos';
  static const location = '/location';
  static const history = '/history';
  static const permissions = '/permissions';
  static const settings = '/settings';
  static const security = '/security';
  static const changePin = '/change-pin';
  static const privacyPolicy = '/privacy-policy';
}

/// Application router.
///
/// Main tab routes are wrapped in a [ShellRoute] providing the bottom
/// navigation bar. The lock screen is the single gate in front of the whole
/// app; a redirect based on the app-lock state keeps everything else
/// unreachable while the app is locked.
final appRouterProvider = Provider<GoRouter>(
  (ref) {
    final router = GoRouter(
      initialLocation: AppRoutes.lock,
      routes: [
        GoRoute(
          path: AppRoutes.lock,
          builder: (context, state) => const LockScreen(),
        ),
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) => const HomeScreen(),
            ),
            GoRoute(
              path: AppRoutes.contacts,
              builder: (context, state) => const ContactsScreen(),
            ),
            GoRoute(
              path: AppRoutes.history,
              builder: (context, state) => const EmergencyHistoryScreen(),
            ),
            GoRoute(
              path: AppRoutes.settings,
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
        GoRoute(
          path: AppRoutes.profile,
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: AppRoutes.sos,
          builder: (context, state) => const SosScreen(),
        ),
        GoRoute(
          path: AppRoutes.location,
          builder: (context, state) => const LocationScreen(),
        ),
        GoRoute(
          path: AppRoutes.permissions,
          builder: (context, state) => const PermissionsScreen(),
        ),
        GoRoute(
          path: AppRoutes.security,
          builder: (context, state) => const SecuritySettingsScreen(),
        ),
        GoRoute(
          path: AppRoutes.changePin,
          builder: (context, state) => const ChangePinScreen(),
        ),
        GoRoute(
          path: AppRoutes.privacyPolicy,
          builder: (context, state) => const PrivacyPolicyScreen(),
        ),
      ],
      redirect: (context, state) {
        final status = ref.read(appLockControllerProvider).status;
        final isUnlocked = status == AppLockStatus.unlocked;
        final onLock = state.uri.path == AppRoutes.lock;
        if (!isUnlocked && !onLock) return AppRoutes.lock;
        if (isUnlocked && onLock) return AppRoutes.home;
        return null;
      },
    );

    // Re-evaluate the redirect whenever the lock state changes.
    ref.listen(appLockControllerProvider, (previous, next) {
      if (previous?.status != next.status) router.refresh();
    });

    return router;
  },
);