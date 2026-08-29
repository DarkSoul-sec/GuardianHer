/// OEM-specific background-run guidance (Phase 3F).
///
/// Maps the native manufacturer token (see
/// `ShakeSosService.manufacturerToken`) to an extra hint line shown under the
/// battery-optimization tile on the Shake SOS screen. Aggressive OEM battery
/// managers kill foreground services even when Android itself would keep them,
/// and each vendor hides the fix behind different switches — this is where the
/// Redmi/MIUI Autostart trap is surfaced. Pure function so the mapping is
/// unit-testable without a device; unknown tokens yield no extra copy.
String? oemBackgroundGuidance(String? token) {
  switch (token) {
    case 'miui':
      return 'Xiaomi / Redmi / POCO: also enable Autostart for GuardianHer '
          '(Settings > Apps > Permissions > Start), or MIUI will stop the '
          'detector.';
    case 'coloros':
      return 'Oppo / OnePlus / realme: allow Auto-launch and set battery usage '
          'to "Do not restrict" for GuardianHer.';
    case 'funtouch':
      return 'Vivo / iQOO: allow Auto-start and "High background power '
          'consumption" for GuardianHer.';
    case 'emui':
      return 'Huawei: enable automatic launch and turn off "Manage '
          'automatically" restrictions in App launch settings.';
    case 'magicos':
      return 'Honor: allow automatic launch and set battery usage to '
          'Unrestricted for GuardianHer.';
    case 'samsung':
      return 'Samsung: remove GuardianHer from Sleeping apps (Battery > '
          'Background usage limits).';
    default:
      return null;
  }
}
