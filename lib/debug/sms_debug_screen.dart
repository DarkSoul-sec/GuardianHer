import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Temporary debug screen to prove SmsManager works on this device.
/// This screen will be removed after the test passes.
class SmsDebugScreen extends StatefulWidget {
  const SmsDebugScreen({super.key});

  @override
  State<SmsDebugScreen> createState() => _SmsDebugScreenState();
}

class _SmsDebugScreenState extends State<SmsDebugScreen> {
  static const _channel = MethodChannel('guardianher/sms_debug');

  final _numberController = TextEditingController();
  final _logs = <String>[];
  bool _sending = false;

  void _log(String msg) {
    debugPrint('[SMS-DEBUG-UI] $msg');
    setState(() => _logs.add(msg));
  }

  Future<void> _sendTestSms() async {
    final number = _numberController.text.trim();
    if (number.isEmpty) {
      _log('ERROR: Enter a phone number');
      return;
    }

    setState(() {
      _sending = true;
      _logs.clear();
    });

    _log('Calling sendTestSms...');
    _log('Number: ${number.length} digits');

    try {
      final result = await _channel.invokeMethod<Map>('sendTestSms', {
        'phoneNumber': number,
        'message': 'GuardianHer automatic SMS test',
      });

      if (result == null) {
        _log('ERROR: null result from MethodChannel');
      } else {
        final success = result['success'] as bool? ?? false;
        final error = result['error'] as String?;
        final resultCode = result['resultCode'];
        final resultDesc = result['resultDescription'] as String?;
        final simCount = result['simCount'];

        _log('success = $success');
        if (resultDesc != null) _log('resultDescription = $resultDesc');
        if (resultCode != null) _log('resultCode = $resultCode');
        if (simCount != null) _log('simCount = $simCount');
        if (error != null) _log('error = $error');

        if (success) {
          _log('');
          _log('SMS submitted to carrier. Check your messages.');
        }
      }
    } on PlatformException catch (e) {
      _log('PlatformException: ${e.message}');
      _log('detail: ${e.details}');
    } catch (e) {
      _log('Exception: $e');
    }

    setState(() => _sending = false);
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Debug Test'),
        backgroundColor: Colors.red[900],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'This test sends ONE automatic SMS.\n'
              'No GPS. No contacts. No background service.\n'
              'Just SmsManager.sendTextMessage().',
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _numberController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Test phone number (with country code)',
                hintText: '+919876543210',
                hintStyle: TextStyle(color: Colors.grey[600]),
                labelStyle: TextStyle(color: Colors.grey[400]),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _sending ? null : _sendTestSms,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[800],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('TEST AUTOMATIC SMS', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 16),
            if (_logs.isNotEmpty) ...[
              Text('Logs:', style: TextStyle(color: Colors.grey[300])),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  color: Colors.black,
                  padding: const EdgeInsets.all(12),
                  child: ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (_, i) => Text(
                      _logs[i],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.greenAccent,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
