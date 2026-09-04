import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/route_guards.dart';
import '../../core/providers.dart';
import '../../features/check_in/presentation/check_in_screen.dart';
import '../../features/check_in/presentation/check_in_settings_screen.dart';
import '../../features/contacts/presentation/contact_form_screen.dart';
import '../../features/contacts/presentation/contacts_screen.dart';
import '../../features/emergency_history/presentation/emergency_history_screen.dart';

import '../../features/journey/presentation/journey_screen.dart';
import '../../features/journey/presentation/map_screen.dart';
import '../../features/location/presentation/location_screen.dart';
import '../../features/onboarding/presentation/screens/permission_onboarding_screen.dart';
import '../../features/onboarding/presentation/screens/splash_screen.dart';
import '../../features/permissions/presentation/permissions_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/safety_recorder/domain/safety_incident.dart';
import '../../features/safety_recorder/presentation/safety_incident_detail_screen.dart';
import '../../features/safety_recorder/presentation/safety_recorder_screen.dart';
import '../../features/settings/presentation/privacy_policy_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/device_admin_settings_screen.dart';
import '../../features/shake/presentation/shake_sos_settings_screen.dart';
import '../../features/sos/presentation/sos_screen.dart';
import '../../shared/widgets/app_shell.dart';
import '../../debug/sms_debug_screen.dart';
import '../home_screen.dart';

/// Central route path registry.
abstract final class AppRoutes {
  AppRoutes._();

  static const splash = '/splash';
  static const home = '/';
  static const profile = '/profile';
  static const contacts = '/contacts';
  static const contactsAdd = '/contacts/add';

  /// Path for editing the contact with [id].
  static String contactsEdit(String id) => '/contacts/edit/$id';
  static const sos = '/sos';
  static const location = '/location';
  static const journey = '/journey';
  static const map = '/map';
  static const checkIn = '/check-in';
  static const checkInSettings = '/check-in/settings';
  static const history = '/history';
  static const permissions = '/permissions';
  static const settings = '/settings';
  static const shakeSosSettings = '/settings/shake-sos';
  static const deviceAdminSettings = '/settings/device-admin';
  static const privacyPolicy = '/privacy-policy';
  static const safetyRecorder = '/safety-recorder';
  static const safetyIncidentDetail = '/safety-recorder/detail';
  static const onboardingPermissions = '/onboarding/permissions';
}

/// Router published before the [ProviderScope] container exists, so the app
/// entrypoint can route notification taps (which carry no `ref`).
GoRouter? publishedRouter;

/// Application router.
///
/// GuardianHer V1 has no app-level authentication gate: the app opens
/// directly to Home and every route (including deep links) is reachable
/// immediately after launch.
final appRouterProvider = Provider<GoRouter>(
  (ref) {
    final router = GoRouter(
      initialLocation: AppRoutes.splash,
      redirect: (context, state) async {
        final isOnSplash = state.matchedLocation == AppRoutes.splash;
        final isOnPermissionScreen = state.matchedLocation == AppRoutes.onboardingPermissions;

        // Don't redirect if already on permission screen
        if (isOnPermissionScreen) return null;

        // Check on splash screen only
        if (isOnSplash) {
          final permissionService = ref.read(permissionServiceProvider);
          final needsOnboarding = await RouteGuards.isOnboardingRequired(
            permissionService: permissionService,
          );
          if (needsOnboarding) {
            return AppRoutes.onboardingPermissions;
          } else {
            return AppRoutes.home;
          }
        }
        return null;
      },
      routes: [
        GoRoute(
          path: AppRoutes.splash,
          builder: (context, state) => const SplashScreen(),
        ),
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) => const HomeScreen(),
            ),
            GoRoute(
              path: AppRoutes.map,
              builder: (context, state) => const MapScreen(),
            ),
            GoRoute(
              path: AppRoutes.journey,
              builder: (context, state) => const JourneyScreen(),
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
          path: AppRoutes.contactsAdd,
          builder: (context, state) => const AddContactScreen(),
        ),
        GoRoute(
          path: '/contacts/edit/:id',
          builder: (context, state) =>
              EditContactScreen(id: state.pathParameters['id']!),
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
          path: AppRoutes.checkIn,
          builder: (context, state) => const CheckInScreen(),
        ),
        GoRoute(
          path: AppRoutes.checkInSettings,
          builder: (context, state) => const CheckInSettingsScreen(),
        ),
        GoRoute(
          path: AppRoutes.permissions,
          builder: (context, state) => const PermissionsScreen(),
        ),
        GoRoute(
          path: AppRoutes.shakeSosSettings,
          builder: (context, state) => const ShakeSosSettingsScreen(),
        ),
        GoRoute(
          path: AppRoutes.deviceAdminSettings,
          builder: (context, state) => const DeviceAdminSettingsScreen(),
        ),
        GoRoute(
          path: AppRoutes.privacyPolicy,
          builder: (context, state) => const PrivacyPolicyScreen(),
        ),
        GoRoute(
          path: AppRoutes.safetyRecorder,
          builder: (context, state) => const SafetyRecorderScreen(),
        ),
        GoRoute(
          path: AppRoutes.safetyIncidentDetail,
          builder: (context, state) {
            final incident = state.extra as SafetyIncident;
            return SafetyIncidentDetailScreen(incident: incident);
          },
        ),
        GoRoute(
          path: AppRoutes.onboardingPermissions,
          builder: (context, state) => const PermissionOnboardingScreen(),
        ),
        // TEMPORARY: SMS debug test — removed after test passes.
        GoRoute(
          path: '/sms-debug',
          builder: (context, state) => const SmsDebugScreen(),
        ),
      ],
    );
    publishedRouter = router;
    return router;
  },
);
