import 'dart:io' show Platform;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppVersionConfig {
  final String minSupportedVersion;
  final String latestVersion;
  final String? updateMessage;
  final String? iosStoreUrl;
  final String? androidStoreUrl;

  AppVersionConfig({
    required this.minSupportedVersion,
    required this.latestVersion,
    this.updateMessage,
    this.iosStoreUrl,
    this.androidStoreUrl,
  });

  factory AppVersionConfig.fromMap(Map<String, dynamic> row) {
    return AppVersionConfig(
      minSupportedVersion: (row['min_supported_version'] as String?) ?? '0.0.0',
      latestVersion: (row['latest_version'] as String?) ?? '0.0.0',
      updateMessage: row['update_message'] as String?,
      iosStoreUrl: row['ios_store_url'] as String?,
      androidStoreUrl: row['android_store_url'] as String?,
    );
  }

  String? get storeUrl => Platform.isIOS ? iosStoreUrl : androidStoreUrl;
}

class VersionCheckResult {
  final bool updateRequired;
  final String currentVersion;
  final AppVersionConfig? config;

  VersionCheckResult({
    required this.updateRequired,
    required this.currentVersion,
    this.config,
  });
}

class VersionService {
  static final VersionService _instance = VersionService._internal();
  factory VersionService() => _instance;
  VersionService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  Future<VersionCheckResult> check() async {
    final info = await PackageInfo.fromPlatform();
    final current = info.version;

    try {
      final row = await _client
          .from('app_config')
          .select('min_supported_version, latest_version, update_message, ios_store_url, android_store_url')
          .eq('id', 1)
          .maybeSingle();

      if (row == null) {
        return VersionCheckResult(updateRequired: false, currentVersion: current);
      }

      final config = AppVersionConfig.fromMap(row);
      final required = _isOlder(current, config.minSupportedVersion);
      return VersionCheckResult(
        updateRequired: required,
        currentVersion: current,
        config: config,
      );
    } catch (_) {
      // Falha de rede / RLS: não bloqueia o usuário. Gate é best-effort —
      // travar o app por intermitência de backend é pior que pular o check.
      return VersionCheckResult(updateRequired: false, currentVersion: current);
    }
  }

  /// Retorna true se `current` é estritamente menor que `minimum`.
  /// Compara MAJOR.MINOR.PATCH numericamente; partes faltantes contam como 0.
  static bool _isOlder(String current, String minimum) {
    final c = _parse(current);
    final m = _parse(minimum);
    for (var i = 0; i < 3; i++) {
      if (c[i] < m[i]) return true;
      if (c[i] > m[i]) return false;
    }
    return false;
  }

  static List<int> _parse(String v) {
    final clean = v.split('+').first.split('-').first;
    final parts = clean.split('.');
    return List.generate(3, (i) {
      if (i >= parts.length) return 0;
      return int.tryParse(parts[i]) ?? 0;
    });
  }
}
