import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/config.dart';

/// عنوان السيرفر والتوكن.
///
/// التوكن سرّ، فبيتخزّن في الـkeystore/keychain مش في shared_preferences.
class SettingsStore {
  SettingsStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(),
            // first_unlock عشان التوكن يبقى متاح للتطبيق بعد أول فتح للجهاز،
            // من غير ما يتاخد في النسخ الاحتياطي للـiCloud.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  Future<String> apiBaseUrl() async {
    final stored = await _storage.read(key: AppConfig.kApiBaseUrl);
    final value = stored?.trim();
    if (value == null || value.isEmpty) return AppConfig.defaultApiBaseUrl;
    return value;
  }

  Future<void> setApiBaseUrl(String value) async {
    // شيل السلاش الأخير عشان ما يبقاش عندنا // في المسارات.
    final cleaned = value.trim().replaceAll(RegExp(r'/+$'), '');
    await _storage.write(key: AppConfig.kApiBaseUrl, value: cleaned);
  }

  Future<String?> apiToken() async {
    final token = await _storage.read(key: AppConfig.kApiToken);
    final value = token?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> setApiToken(String value) =>
      _storage.write(key: AppConfig.kApiToken, value: value.trim());

  /// التطبيق مضبوط ولا لسه محتاج شاشة الإعداد؟
  Future<bool> isConfigured() async => (await apiToken()) != null;
}
