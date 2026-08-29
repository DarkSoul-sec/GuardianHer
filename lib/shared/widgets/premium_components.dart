import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Glass Card
// ─────────────────────────────────────────────────────────────────────────────

/// A translucent card with subtle border and frosted-glass aesthetic.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    this.child,
    this.padding = const EdgeInsets.all(16),
    this.elevated = false,
    this.borderRadius,
  });

  final Widget? child;
  final EdgeInsetsGeometry padding;
  final bool elevated;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: elevated
            ? AppTheme.glassFillElevated
            : AppTheme.glassFill,
        borderRadius: borderRadius ?? BorderRadius.circular(16),
        border: Border.all(
          color: elevated
              ? AppTheme.glassBorder.withValues(alpha: 0.2)
              : AppTheme.glassBorder.withValues(alpha: 0.1),
          width: 0.5,
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Glow Ring — animated pulsing ring for SOS / protection indicator
// ─────────────────────────────────────────────────────────────────────────────

/// An animated ring that pulses around a child widget. Used for the
/// protection-active indicator around the SOS button and as a generic
/// "system active" visual cue.
class GlowRing extends StatefulWidget {
  const GlowRing({
    super.key,
    required this.child,
    this.color = AppTheme.violet,
    this.ringWidth = 3,
    this.minPadding = 6,
    this.animate = true,
  });

  final Widget child;
  final Color color;
  final double ringWidth;
  final double minPadding;
  final bool animate;

  @override
  State<GlowRing> createState() => _GlowRingState();
}

class _GlowRingState extends State<GlowRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _pulse = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.animate) _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glow = widget.color;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final p = _pulse.value;
        return Container(
          padding: EdgeInsets.all(widget.minPadding + widget.ringWidth),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: glow.withValues(alpha: 0.35 * p),
                blurRadius: 24 * p,
                spreadRadius: 4 * p,
              ),
              BoxShadow(
                color: glow.withValues(alpha: 0.15 * p),
                blurRadius: 48 * p,
                spreadRadius: 8 * p,
              ),
            ],
          ),
          child: Container(
            padding: EdgeInsets.all(widget.ringWidth),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  glow.withValues(alpha: 0.6 * p),
                  glow.withValues(alpha: 0.2),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status Indicator
// ─────────────────────────────────────────────────────────────────────────────

enum StatusLevel { active, warning, critical, info, neutral }

class StatusIndicator extends StatelessWidget {
  const StatusIndicator({
    super.key,
    required this.label,
    this.level = StatusLevel.active,
    this.trailing,
  });

  final String label;
  final StatusLevel level;
  final Widget? trailing;

  Color _dotColor() => switch (level) {
        StatusLevel.active => AppTheme.successGreen,
        StatusLevel.warning => AppTheme.warningAmber,
        StatusLevel.critical => AppTheme.sosRed,
        StatusLevel.info => AppTheme.infoCyan,
        StatusLevel.neutral => AppTheme.textMuted,
      };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _dotColor(),
            boxShadow: [
              BoxShadow(color: _dotColor().withValues(alpha: 0.5), blurRadius: 6),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Header
// ─────────────────────────────────────────────────────────────────────────────

class PremiumSectionHeader extends StatelessWidget {
  const PremiumSectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, top: 8, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
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
// Quick Action Card (4-tile grid)
// ─────────────────────────────────────────────────────────────────────────────

class QuickActionCard extends StatelessWidget {
  const QuickActionCard({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppTheme.violetLight;
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.15),
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Emergency SOS Button — large circular with gradient + glow
// ─────────────────────────────────────────────────────────────────────────────

class SosButton extends StatelessWidget {
  const SosButton({
    super.key,
    required this.onPressed,
    this.radius = 72,
    this.animate = true,
  });

  final VoidCallback onPressed;
  final double radius;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onPressed,
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [AppTheme.sosRed, AppTheme.sosRedDark],
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.sosRedGlow,
              blurRadius: 32,
              spreadRadius: 8,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shield_outlined,
              color: Colors.white.withValues(alpha: 0.9),
              size: 36,
            ),
            const SizedBox(height: 4),
            const Text(
              'SOS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            Text(
              'Tap to Alert',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );

    if (!animate) return button;
    return GlowRing(
      color: AppTheme.sosRed,
      ringWidth: 2,
      minPadding: 8,
      child: button,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hold-to-Confirm Button — used for destructive / emergency stop actions
// ─────────────────────────────────────────────────────────────────────────────

class HoldToConfirmButton extends StatefulWidget {
  const HoldToConfirmButton({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.color = AppTheme.sosRed,
    this.holdDuration = const Duration(milliseconds: 1500),
    this.icon,
  });

  final String label;
  final VoidCallback onConfirmed;
  final Color color;
  final Duration holdDuration;
  final IconData? icon;

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<HoldToConfirmButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressCtrl;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(
      vsync: this,
      duration: widget.holdDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onConfirmed();
        }
      });
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent _) {
    setState(() => _holding = true);
    _progressCtrl.forward();
  }

  void _onPointerUp(PointerUpEvent _) => _cancel();
  void _onPointerCancel(PointerCancelEvent _) => _cancel();

  void _cancel() {
    setState(() => _holding = false);
    _progressCtrl.stop();
    _progressCtrl.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: AnimatedBuilder(
        animation: _progressCtrl,
        builder: (context, _) {
          final progress = _progressCtrl.value;
          return Container(
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: widget.color.withValues(alpha: 0.15 + 0.85 * progress),
              border: Border.all(
                color: widget.color.withValues(alpha: 0.4 + 0.6 * progress),
                width: 1,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (progress > 0)
                  Positioned.fill(
                    child: FractionallySizedBox(
                      widthFactor: progress,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: widget.color.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null)
                      Icon(
                        widget.icon,
                        color: Colors.white.withValues(
                          alpha: 0.6 + 0.4 * progress,
                        ),
                        size: 20,
                      ),
                    if (widget.icon != null) const SizedBox(width: 8),
                    Text(
                      _holding ? 'Keep holding…' : widget.label,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grid Divider — subtle horizontal line with glow dot
// ─────────────────────────────────────────────────────────────────────────────

class GlowDivider extends StatelessWidget {
  const GlowDivider({super.key, this.color = AppTheme.violet});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    color.withValues(alpha: 0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.4),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.2),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    color.withValues(alpha: 0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shield Icon — branded brand mark replacement
// ─────────────────────────────────────────────────────────────────────────────

class ShieldIcon extends StatelessWidget {
  const ShieldIcon({
    super.key,
    this.size = 32,
    this.color = AppTheme.violetLight,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.shield_outlined,
      size: size,
      color: color,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ambient Background — subtle grid + radial glow for premium screens
// ─────────────────────────────────────────────────────────────────────────────

class AmbientBackground extends StatelessWidget {
  const AmbientBackground({
    super.key,
    this.child,
    this.centerGlowColor,
    this.centerGlowRadius = 200,
  });

  final Widget? child;
  final Color? centerGlowColor;
  final double centerGlowRadius;

  @override
  Widget build(BuildContext context) {
    final glow = centerGlowColor ?? AppTheme.violet;
    return Stack(
      children: [
        // Subtle grid overlay
        CustomPaint(
          painter: _GridPainter(),
          size: Size.infinite,
        ),
        // Radial glow at top-center
        Positioned(
          top: -centerGlowRadius,
          left: 0,
          right: 0,
          height: centerGlowRadius * 2,
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  glow.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.glassBorder.withValues(alpha: 0.04)
      ..strokeWidth = 0.5;

    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
