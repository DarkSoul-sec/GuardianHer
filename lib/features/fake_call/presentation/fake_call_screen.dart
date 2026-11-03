import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/guardianher_design.dart';
import '../application/fake_call_providers.dart';
import '../domain/fake_call_config.dart';
import '../domain/fake_call_state.dart';
import 'fake_call_incoming_screen.dart';

/// Fake Call configuration screen.
///
/// Display-only caller details, closed delay set, vibration toggle and a
/// schedule button. When the controller is ringing/active this route shows
/// the incoming-call screen instead (same route, state-driven).
class FakeCallScreen extends ConsumerStatefulWidget {
  const FakeCallScreen({super.key});

  @override
  ConsumerState<FakeCallScreen> createState() => _FakeCallScreenState();
}

class _FakeCallScreenState extends ConsumerState<FakeCallScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _numberController;
  FakeCallDelay _delay = FakeCallDelay.seconds10;
  bool _vibration = true;

  @override
  void initState() {
    super.initState();
    const defaults = FakeCallConfig();
    _nameController = TextEditingController(text: defaults.callerName);
    _numberController = TextEditingController(text: defaults.callerNumber);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fakeCallControllerProvider);
    return switch (state) {
      FakeCallRinging() || FakeCallActive() => const FakeCallIncomingScreen(),
      _ => _buildConfig(context, ref, state),
    };
  }

  Widget _buildConfig(
      BuildContext context, WidgetRef ref, FakeCallState state) {
    final scheduled = state is FakeCallScheduled ? state : null;
    final ended = state is FakeCallEnded ? state : null;

    return Scaffold(
      backgroundColor: AppTheme.appBackground,
      appBar: AppBar(
        title: Text(
          'Fake Call',
          style: GoogleFonts.inter(
            color: AppTheme.guardianIndigo,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Simulate an incoming call. Nothing is dialled, sent, or recorded — entirely on this device.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppTheme.textBody,
              ),
            ),
            const SizedBox(height: 20),
            if (scheduled != null)
              _ScheduledBanner(
                fireAt: scheduled.fireAt,
                onCancel: () => ref
                    .read(fakeCallControllerProvider.notifier)
                    .cancelFakeCall(),
              ),
            if (ended != null) _EndedBanner(reason: ended.reason),
            if (scheduled != null || ended != null) const SizedBox(height: 16),
            const GhSectionTitle(title: 'Caller'),
            GhCard(
              child: Column(
                children: [
                  TextField(
                    key: const Key('fake-call-name'),
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Caller name',
                      hintText: 'Mom',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('fake-call-number'),
                    controller: _numberController,
                    decoration: const InputDecoration(
                      labelText: 'Caller number (display only)',
                      hintText: 'Incoming Call',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const GhSectionTitle(title: 'Delay'),
            ...FakeCallDelay.values.map(
              (d) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _DelayOption(
                  label: d.label,
                  selected: _delay == d,
                  onTap: () => setState(() => _delay = d),
                ),
              ),
            ),
            const SizedBox(height: 12),
            GhCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Vibration',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.guardianIndigo,
                      ),
                    ),
                  ),
                  Switch(
                    key: const Key('fake-call-vibration'),
                    value: _vibration,
                    activeThumbColor: AppTheme.guardianIndigo,
                    onChanged: (v) => setState(() => _vibration = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('fake-call-schedule'),
              onPressed: scheduled != null
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      final config = FakeCallConfig(
                        callerName: _nameController.text.trim().isEmpty
                            ? 'Mom'
                            : _nameController.text.trim(),
                        callerNumber: _numberController.text.trim().isEmpty
                            ? 'Incoming Call'
                            : _numberController.text.trim(),
                        delay: _delay,
                        vibrationEnabled: _vibration,
                      );
                      ref
                          .read(fakeCallControllerProvider.notifier)
                          .scheduleFakeCall(config);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Fake call scheduled for ${_delay.label}.',
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.schedule_outlined),
              label: const Text('Schedule Fake Call'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DelayOption extends StatelessWidget {
  const _DelayOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.lavenderSoft
              : AppTheme.appBackgroundAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.guardianIndigo : AppTheme.borderLight,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: AppTheme.guardianIndigo,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle,
                size: 20,
                color: AppTheme.guardianIndigo,
              ),
          ],
        ),
      ),
    );
  }
}

class _ScheduledBanner extends StatelessWidget {
  const _ScheduledBanner({required this.fireAt, required this.onCancel});

  final DateTime fireAt;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return GhCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.lavenderSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.schedule_outlined,
              color: AppTheme.guardianIndigo,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Fake call scheduled.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            key: const Key('fake-call-cancel'),
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _EndedBanner extends ConsumerWidget {
  const _EndedBanner({super.key, required this.reason});

  final FakeCallEndReason reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = switch (reason) {
      FakeCallEndReason.declined => 'Fake call declined.',
      FakeCallEndReason.hungUp => 'Fake call ended.',
      FakeCallEndReason.timedOut => 'Fake call ended (no answer).',
      FakeCallEndReason.cancelled => 'Fake call cancelled.',
    };
    return GhCard(
      child: Row(
        children: [
          const Icon(
            Icons.call_end_outlined,
            color: AppTheme.textBody,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
          TextButton(
            onPressed: () =>
                ref.read(fakeCallControllerProvider.notifier).dismiss(),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }
}
