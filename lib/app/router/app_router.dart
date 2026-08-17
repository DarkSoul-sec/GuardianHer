import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_screen.dart';
import '../../features/contacts/presentation/contacts_screen.dart';
import '../../features/emergency_history/presentation/emergency_history_screen.dart';
import '../../features/location/presentation/location_screen.dart';
import '../../features/permissions/presentation/permissions_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/sos/presentation/sos_screen.dart';
import '../../shared/widgets/app_shell.dart';
import '../home_screen.dart';

/// Central route path registry.
abstract final class AppRoutes {
  AppRoutes._();

  static const home = '/';
  static const auth = '/auth';
  static const profile = '/profile';
  static const contacts = '/contacts';
  static const sos = '/sos';
  static const location = '/location';
  static const history = '/history';
  static const permissions = '/permissions';
  static const settings = '/settings';
}

/// Application router.
///
/// Main tab routes are wrapped in a [ShellRoute] providing the bottom
/// navigation bar. Flows that need a full-screen context (SOS, auth, etc.)
/// are declared at the top level.
final appRouterProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
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
        path: AppRoutes.auth,
        builder: (context, state) => const AuthScreen(),
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
    ],
  ),
);