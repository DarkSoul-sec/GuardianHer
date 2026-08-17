/// Basic application identity information for display purposes.
class AppInfo {
  const AppInfo({
    required this.appName,
    required this.version,
    required this.buildNumber,
  });

  final String appName;
  final String version;
  final String buildNumber;
}

/// Abstraction over package/app identity lookup.
///
/// Backed by package_info_plus.
abstract interface class AppInfoService {
  Future<AppInfo> getAppInfo();
}