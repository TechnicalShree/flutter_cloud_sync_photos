import 'package:shared_preferences/shared_preferences.dart';

class UploadPreferences {
  const UploadPreferences({
    required this.isPrivate,
    required this.optimize,
    required this.wifiOnly,
    required this.whileCharging,
    required this.blockOnRoaming,
    required this.batteryThreshold,
  });

  final bool isPrivate;
  final bool optimize;
  final bool wifiOnly;
  final bool whileCharging;
  final bool blockOnRoaming;
  final int batteryThreshold;

  UploadPreferences copyWith({
    bool? isPrivate,
    bool? optimize,
    bool? wifiOnly,
    bool? whileCharging,
    bool? blockOnRoaming,
    int? batteryThreshold,
  }) {
    return UploadPreferences(
      isPrivate: isPrivate ?? this.isPrivate,
      optimize: optimize ?? this.optimize,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      whileCharging: whileCharging ?? this.whileCharging,
      blockOnRoaming: blockOnRoaming ?? this.blockOnRoaming,
      batteryThreshold: batteryThreshold ?? this.batteryThreshold,
    );
  }
}

class UploadPreferencesStore {
  UploadPreferencesStore({SharedPreferences? preferences})
    : _prefsFuture = preferences != null
          ? Future.value(preferences)
          : SharedPreferences.getInstance();

  static const String _isPrivateKey = 'upload_pref_is_private';
  static const String _optimizeKey = 'upload_pref_optimize';
  static const String _wifiOnlyKey = 'upload_pref_wifi_only';
  static const String _whileChargingKey = 'upload_pref_while_charging';
  static const String _blockOnRoamingKey = 'upload_pref_block_on_roaming';
  static const String _batteryThresholdKey = 'upload_pref_battery_threshold';

  final Future<SharedPreferences> _prefsFuture;

  Future<UploadPreferences> load() async {
    final prefs = await _prefsFuture;
    final isPrivate = prefs.getBool(_isPrivateKey) ?? true;
    final optimize = prefs.getBool(_optimizeKey) ?? false;
    final wifiOnly = prefs.getBool(_wifiOnlyKey) ?? false;
    final whileCharging = prefs.getBool(_whileChargingKey) ?? false;
    final blockOnRoaming = prefs.getBool(_blockOnRoamingKey) ?? false;
    final storedThreshold = prefs.getInt(_batteryThresholdKey);
    final batteryThreshold = storedThreshold == null
        ? 0
        : storedThreshold.clamp(0, 100);
    return UploadPreferences(
      isPrivate: isPrivate,
      optimize: optimize,
      wifiOnly: wifiOnly,
      whileCharging: whileCharging,
      blockOnRoaming: blockOnRoaming,
      batteryThreshold: batteryThreshold,
    );
  }

  Future<void> setIsPrivate(bool value) async {
    final prefs = await _prefsFuture;
    await prefs.setBool(_isPrivateKey, value);
  }

  Future<void> setOptimize(bool value) async {
    final prefs = await _prefsFuture;
    await prefs.setBool(_optimizeKey, value);
  }

  Future<void> setWifiOnly(bool value) async {
    final prefs = await _prefsFuture;
    await prefs.setBool(_wifiOnlyKey, value);
  }

  Future<void> setWhileCharging(bool value) async {
    final prefs = await _prefsFuture;
    await prefs.setBool(_whileChargingKey, value);
  }

  Future<void> setBlockOnRoaming(bool value) async {
    final prefs = await _prefsFuture;
    await prefs.setBool(_blockOnRoamingKey, value);
  }

  Future<void> setBatteryThreshold(int value) async {
    final prefs = await _prefsFuture;
    final clamped = value.clamp(0, 100);
    await prefs.setInt(_batteryThresholdKey, clamped);
  }

  Future<void> update({
    bool? isPrivate,
    bool? optimize,
    bool? wifiOnly,
    bool? whileCharging,
    bool? blockOnRoaming,
    int? batteryThreshold,
  }) async {
    final prefs = await _prefsFuture;
    if (isPrivate != null) {
      await prefs.setBool(_isPrivateKey, isPrivate);
    }
    if (optimize != null) {
      await prefs.setBool(_optimizeKey, optimize);
    }
    if (wifiOnly != null) {
      await prefs.setBool(_wifiOnlyKey, wifiOnly);
    }
    if (whileCharging != null) {
      await prefs.setBool(_whileChargingKey, whileCharging);
    }
    if (blockOnRoaming != null) {
      await prefs.setBool(_blockOnRoamingKey, blockOnRoaming);
    }
    if (batteryThreshold != null) {
      final clamped = batteryThreshold.clamp(0, 100);
      await prefs.setInt(_batteryThresholdKey, clamped);
    }
  }
}

final UploadPreferencesStore uploadPreferencesStore = UploadPreferencesStore();
