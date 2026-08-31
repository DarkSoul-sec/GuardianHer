import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'whatsapp_datasource.dart';

/// Re-export [WhatsAppDataSource] for consumers of this provider.
export 'whatsapp_datasource.dart';

/// Provider for the [WhatsAppDataSource] that opens emergency WhatsApp chats.
final whatsAppDataSourceProvider = Provider<WhatsAppDataSource>((ref) => WhatsAppDataSource());