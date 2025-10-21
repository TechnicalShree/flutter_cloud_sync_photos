import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_cloud_sync_photos/features/auth/data/services/session_manager.dart';
import 'package:flutter_cloud_sync_photos/features/auth/domain/models/user_details.dart';

class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage({this.shouldThrow = false});

  final bool shouldThrow;
  final Map<String, String?> _store = <String, String?>{};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) {
      throw const MissingPluginException('unavailable');
    }
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) {
      throw const MissingPluginException('unavailable');
    }
    return _store[key];
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) {
      throw const MissingPluginException('unavailable');
    }
    _store.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('SessionManager', () {
    test('persists and loads cookies when secure storage succeeds', () async {
      final manager = SessionManager(secureStorage: _FakeSecureStorage());

      await manager.persistCookies(<String, String>{'sid': 'cookie'});

      final cookies = await manager.loadCookies();
      expect(cookies, <String, String>{'sid': 'cookie'});
    });

    test('falls back to SharedPreferences when secure storage unavailable', () async {
      final manager = SessionManager(secureStorage: _FakeSecureStorage(shouldThrow: true));
      final details = UserDetails(name: 'Test User', user: 'tester');

      await manager.persistUserDetails(details);

      final loaded = await manager.loadUserDetails();
      expect(loaded?.name, 'Test User');
      expect(loaded?.user, 'tester');
    });
  });
}
