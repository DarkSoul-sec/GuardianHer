import 'package:package_info_plus/package_info_plus.dart';

import '../../core/platform/app_info_service.dart';

/// App identity backed by package_info_plus.
class PackageInfoAppInfoService implements AppInfoService {
  const PackageInfoAppInfoService();

  @override
  Future<AppInfo> getAppInfo() async {
    final info = await PackageInfo.fromPlatform();
    return AppInfo(
      appName: info.appName,
      version: info.version,
      buildNumber: info.buildNumber,
    );
  }
}