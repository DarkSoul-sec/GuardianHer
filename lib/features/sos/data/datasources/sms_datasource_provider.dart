import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sms_datasource.dart';

/// Provider for the [SmsDataSource] that sends emergency SMS via telephony.
final smsDataSourceProvider = Provider<SmsDataSource>((ref) => SmsDataSource());