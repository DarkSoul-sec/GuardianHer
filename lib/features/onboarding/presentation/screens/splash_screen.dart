import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:guardianher/app/router/app_router.dart';
import 'package:guardianher/core/routing/route_guards.dart';
import 'package:guardianher/app/theme/app_theme.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAndRedirect();
  }

  Future<void> _checkAndRedirect() async {
    // Small delay to show splash
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final needsOnboarding = await RouteGuards.isOnboardingRequired();
    if (!mounted) return;

    if (needsOnboarding) {
      context.go(AppRoutes.onboardingPermissions);
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.appBackground,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/brand/logo.png',
              width: 120,
              height: 120,
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                AppTheme.guardianIndigo,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textBody,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}