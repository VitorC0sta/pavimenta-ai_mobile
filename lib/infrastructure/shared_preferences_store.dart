import 'package:shared_preferences/shared_preferences.dart';

import '../application/e3_storage_ports.dart';

/// [PreferencesStore] adapter backed by the platform shared preferences.
///
/// It is intentionally limited to non-secret strings. E3 configuration
/// serialization, validation, and versioning belong to the repository task.
final class SharedPreferencesStore implements PreferencesStore {
  SharedPreferencesStore(this._preferences);

  final SharedPreferences _preferences;

  static Future<SharedPreferencesStore> create() async =>
      SharedPreferencesStore(await SharedPreferences.getInstance());

  @override
  Future<String?> getString(String key) async => _preferences.getString(key);

  @override
  Future<bool> setString(String key, String value) =>
      _preferences.setString(key, value);

  @override
  Future<bool> remove(String key) => _preferences.remove(key);
}
