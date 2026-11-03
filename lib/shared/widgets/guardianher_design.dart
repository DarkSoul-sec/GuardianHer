import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_theme.dart';

/// GuardianHer premium light design system.
///
/// Warm off-white + deep indigo + soft lavender + coral SOS.
/// All radii 22–28px, soft low-opacity shadows, generous whitespace.
/// These widgets are additive — legacy `premium_components.dart` is untouched
/// so existing screens keep compiling and existing tests keep passing.

// ─────────────────────────────────────────────────────────────────────────────
// GH Card — warm-white rounded card with soft shadow
// ─────────────────────────────────────────────────────────────────────────────

class GhCard extends StatelessWidget {
  const GhCard({
    super.key,
    this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.borderRadius = 24,
  });

  final Widget? child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppTheme.borderLight),
        boxShadow: AppTheme.softShadow(),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap!();
        },
        borderRadius: BorderRadius.circular(borderRadius),
        child: body,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GH Section title — small uppercase bold
// ─────────────────────────────────────────────────────────────────────────────

class GhSectionTitle extends StatelessWidget {
  const GhSectionTitle({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: AppTheme.guardianIndigo,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GH SOS Button — 2-second hold with circular progress + haptics.
// Tap navigates (handled by caller via onTap); hold arms SOS via onHoldComplete.
// ─────────────────────────────────────────────────────────────────────────────

class GhSosButton extends StatefulWidget {
  const GhSosButton({
    super.key,
    required this.onHoldComplete,
    this.onTap,
    this.diameter = 220,
    this.holdDuration = const Duration(seconds: 2),
    this.enabled = true,
  });

  final VoidCallback onHoldComplete;
  final VoidCallback? onTap;
  final double diameter;
  final Duration holdDuration;
  final bool enabled;

  @override
  State<GhSosButton> createState() => _GhSosButtonState();
}

class _GhSosButtonState extends State<GhSosButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: widget.holdDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && _holding) {
          HapticFeedback.heavyImpact();
          widget.onHoldComplete();
          _cancel(silent: true);
        }
      });
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _beginHold() {
    if (!widget.enabled) return;
    setState(() => _holding = true);
    HapticFeedback.mediumImpact();
    _progress.forward(from: 0);
  }

  void _cancel({bool silent = false}) {
    if (!mounted) return;
    setState(() => _holding = false);
    _progress.stop();
    _progress.reset();
    if (!silent) HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.diameter;
    return Semantics(
      label: 'SOS. Hold for 2 seconds to activate emergency SOS',
      button: true,
      child: GestureDetector(
        onLongPressStart: (_) => _beginHold(),
        onLongPressEnd: (_) => _cancel(),
        onLongPressCancel: () => _cancel(),
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedBuilder(
          animation: _progress,
          builder: (context, _) {
            final p = _progress.value;
            final scale = _holding ? 1.0 + 0.03 * p : 1.0;
            return Transform.scale(
              scale: scale,
              child: SizedBox(
                width: d + 48,
                height: d + 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Soft coral glow
                    Container(
                      width: d + 44,
                      height: d + 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.sosCoralGlow.withValues(
                          alpha: 0.35 + 0.45 * p,
                        ),
                      ),
                    ),
                    // Subtle outer rings
                    Container(
                      width: d + 28,
                      height: d + 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.sosCoral.withValues(alpha: 0.25),
                          width: 1.5,
                        ),
                      ),
                    ),
                    Container(
                      width: d + 12,
                      height: d + 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.sosCoral.withValues(
                            alpha: 0.35 + 0.3 * p,
                          ),
                          width: 2,
                        ),
                      ),
                    ),
                    // Progress ring (only while holding; an indeterminate
                    // spinner would never settle under pumpAndSettle).
                    if (p > 0)
                      SizedBox(
                        width: d + 4,
                        height: d + 4,
                        child: CircularProgressIndicator(
                          value: p,
                          strokeWidth: 5,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppTheme.sosCoral.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    // Coral button
                    Container(
                      width: d,
                      height: d,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.sosCoral,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.sosCoral.withValues(alpha: 0.45),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.shield_outlined,
                            color: Colors.white,
                            size: 52,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'SOS',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GH Quick action card — lavender icon chip, centered content
// ─────────────────────────────────────────────────────────────────────────────

class GhQuickAction extends StatelessWidget {
  const GhQuickAction({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: enabled ? AppTheme.lavenderSoft : AppTheme.appBackgroundMuted,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            icon,
            size: 24,
            color: enabled ? AppTheme.guardianIndigo : AppTheme.textFaint,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: enabled ? AppTheme.guardianIndigo : AppTheme.textFaint,
          ),
        ),
      ],
    );
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: GhCard(
        onTap: enabled ? onTap : null,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: content,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GH Contact card — photo, name, coral call button
// ─────────────────────────────────────────────────────────────────────────────

class GhContactCard extends StatelessWidget {
  const GhContactCard({
    super.key,
    required this.name,
    this.onTap,
    this.onCall,
  });

  final String name;
  final VoidCallback? onTap;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    return GhCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: SizedBox(
        width: 104,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.lavenderSoft,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: GoogleFonts.inter(
                      color: AppTheme.guardianIndigo,
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: onCall == null
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            onCall!();
                          },
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.sosCoral,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: AppTheme.softShadow(opacity: 0.15),
                      ),
                      child: const Icon(Icons.call, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.guardianIndigo,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GH shield logo — lavender rounded square + shield/lock
// ─────────────────────────────────────────────────────────────────────────────

/// GuardianHer brand mark: deep-indigo shield with a centered check on a
/// soft lavender rounded square. Single symbol, no lock overlay.
class GhLogo extends StatelessWidget {
  const GhLogo({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.lavenderSoft,
            AppTheme.lavenderMid.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(
          color: AppTheme.lavenderDeep.withValues(alpha: 0.5),
        ),
        boxShadow: AppTheme.softShadow(opacity: 0.1),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.shield_rounded,
            size: size * 0.58,
            color: AppTheme.guardianIndigo,
          ),
          Icon(
            Icons.check_rounded,
            size: size * 0.26,
            color: AppTheme.surfaceWhite,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GH status dot — subtle green pulse for "You are safe"
// ─────────────────────────────────────────────────────────────────────────────

class GhSafetyDot extends StatefulWidget {
  const GhSafetyDot({super.key});

  @override
  State<GhSafetyDot> createState() => _GhSafetyDotState();
}

class _GhSafetyDotState extends State<GhSafetyDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // Single finite pulse (not infinite): widget tests use pumpAndSettle,
    // which never completes while an animation is still ticking.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.successGreen,
          boxShadow: [
            BoxShadow(
              color: AppTheme.successGreen.withValues(
                alpha: 0.3 + 0.3 * _ctrl.value,
              ),
              blurRadius: 6 + 4 * _ctrl.value,
            ),
          ],
        ),
      ),
    );
  }
}
