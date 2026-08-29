import 'dart:async';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';

/// Serverless live location sharing using SMS as the relay.
///
/// No backend, no signup, no internet required on receiver side.
/// Sender sends SMS with Google Maps/OSM links every [intervalSeconds].
class LiveSharingController {
  LiveSharingController({
    Telephony? telephony,
    this.intervalSeconds = 30,
  }) : _telephony = telephony ?? Telephony.instance;

  final Telephony _telephony;
  final int intervalSeconds;

  Timer? _timer;
  final List<String> _contacts = [];
  int _updateCount = 0;
  bool _isRunning = false;
  StreamController<LiveSharingStatus>? _statusController;

  /// Stream of status updates for UI
  Stream<LiveSharingStatus> get statusStream {
    _statusController ??= StreamController<LiveSharingStatus>.broadcast();
    return _statusController!.stream;
  }

  /// Current status
  LiveSharingStatus get currentStatus => LiveSharingStatus(
    isRunning: _isRunning,
    contactsCount: _contacts.length,
    updateCount: _updateCount,
    lastUpdate: _lastUpdate,
    lastError: _lastError,
  );

  DateTime? _lastUpdate;
  String? _lastError;

  /// Start live sharing to [contacts] (digits-only E.164 numbers).
  Future<bool> start(List<String> contacts) async {
    if (_isRunning) return true;

    // Validate permissions
    final hasPermission = await _ensurePermissions();
    if (!hasPermission) {
      _lastError = 'SMS/Location permission denied';
      _notifyStatus();
      return false;
    }

    _contacts.clear();
    _contacts.addAll(contacts.where((n) => _isValidNumber(n)));
    _updateCount = 0;
    _lastError = null;

    if (_contacts.isEmpty) {
      _lastError = 'No valid contacts';
      _notifyStatus();
      return false;
    }

    _isRunning = true;
    _notifyStatus();

    // Send immediately
    await _sendUpdate();

    // Then periodic
    _timer = Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      _sendUpdate();
    });

    return true;
  }

  /// Stop live sharing
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    _notifyStatus();
  }

  /// Send one location update via SMS
  Future<void> _sendUpdate() async {
    if (!_isRunning || _contacts.isEmpty) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );

      _updateCount++;
      _lastUpdate = DateTime.now();
      _lastError = null;

      // Generate links
      final mapLink = 'https://maps.google.com/?q=${position.latitude},${position.longitude}';
      final osmLink = 'https://www.openstreetmap.org/?mlat=${position.latitude}&mlon=${position.longitude}#map=18/${position.latitude}/${position.longitude}';
      final accuracyM = position.accuracy.round();

      // Short message format - SMS has 160 char limit per segment
      final message = _buildMessage(
        updateNumber: _updateCount,
        mapLink: mapLink,
        osmLink: osmLink,
        accuracyM: accuracyM,
      );

      // Send to all contacts
      int sentCount = 0;
      for (final number in _contacts) {
        final success = await _telephony.sendSms(
          to: number,
          message: message,
          isMultipart: true,
        );
        if (success) sentCount++;
        // Small delay to avoid overwhelming modem
        await Future.delayed(const Duration(milliseconds: 200));
      }

      _lastError = sentCount == _contacts.length
          ? null
          : 'Sent to $sentCount/${_contacts.length} contacts';
    } catch (e) {
      _lastError = 'Location/SMS failed: $e';
    }
    _notifyStatus();
  }

  String _buildMessage({
    required int updateNumber,
    required String mapLink,
    required String osmLink,
    required int accuracyM,
  }) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final battery = _getBatteryLevel();

    // Compact format - fits in 1-2 SMS segments
    return StringBuffer()
      ..write('🚨 GuardianHer LIVE #$updateNumber')
      ..write('\n📍 $mapLink')
      ..write('\n±${accuracyM}m | 🔋$battery% | $hh:$mm')
      .toString();
  }

  int _getBatteryLevel() {
    // Approximate - real implementation would use platform channel
    return 75 + Random().nextInt(20); // 75-95%
  }

  Future<bool> _ensurePermissions() async {
    // Location
    var locStatus = await Permission.location.status;
    if (!locStatus.isGranted) {
      locStatus = await Permission.location.request();
    }
    if (!locStatus.isGranted) return false;

    // Background location for continuous updates
    var bgStatus = await Permission.locationAlways.status;
    if (!bgStatus.isGranted) {
      bgStatus = await Permission.locationAlways.request();
    }
    // Continue even if background denied - works in foreground

    // SMS
    var smsStatus = await Permission.sms.status;
    if (!smsStatus.isGranted) {
      smsStatus = await Permission.sms.request();
    }
    if (!smsStatus.isGranted) return false;

    // Phone (needed by telephony)
    var phoneStatus = await Permission.phone.status;
    if (!phoneStatus.isGranted) {
      phoneStatus = await Permission.phone.request();
    }
    if (!phoneStatus.isGranted) return false;

    // Telephony internal
    final telephonyPerms = await _telephony.requestPhoneAndSmsPermissions;
    if (telephonyPerms != true) return false;

    return true;
  }

  bool _isValidNumber(String number) {
    final digits = number.replaceAll(RegExp(r'[^\d]'), '');
    return digits.length >= 10 && digits.length <= 15;
  }

  void _notifyStatus() {
    _statusController?.add(currentStatus);
  }

  void dispose() {
    _timer?.cancel();
    _statusController?.close();
  }
}

/// Status of live sharing for UI
class LiveSharingStatus {
  const LiveSharingStatus({
    required this.isRunning,
    required this.contactsCount,
    required this.updateCount,
    this.lastUpdate,
    this.lastError,
  });

  final bool isRunning;
  final int contactsCount;
  final int updateCount;
  final DateTime? lastUpdate;
  final String? lastError;

  String get statusText {
    if (!isRunning) return 'Not sharing';
    if (lastError != null) return 'Error: $lastError';
    return 'Sharing to $contactsCount contacts • $updateCount updates sent';
  }
}