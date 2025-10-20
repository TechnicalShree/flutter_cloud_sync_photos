import 'package:shared_preferences/shared_preferences.dart';

class UploadPreferences {
  const UploadPreferences({required this.isPrivate, required this.optimize});

  final bool isPrivate;
  final bool optimize;

  UploadPreferences copyWith({bool? isPrivate, bool? optimize}) {
    return UploadPreferences(
      isPrivate: isPrivate ?? this.isPrivate,
      optimize: optimize ?? this.optimize,
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

  final Future<SharedPreferences> _prefsFuture;

  Future<UploadPreferences> load() async {
    final prefs = await _prefsFuture;
    final isPrivate = prefs.getBool(_isPrivateKey) ?? true;
    final optimize = prefs.getBool(_optimizeKey) ?? false;
    return UploadPreferences(isPrivate: isPrivate, optimize: optimize);
  }

  Future<void> setIsPrivate(bool value) async {
    final prefs = await _prefsFuture;
    await prefs.setBool(_isPrivateKey, value);
  }

  Future<void> setOptimize(bool value) async {
    final prefs = await _prefsFuture;
    await prefs.setBool(_optimizeKey, value);
  }

  Future<void> update({bool? isPrivate, bool? optimize}) async {
    final prefs = await _prefsFuture;
    if (isPrivate != null) {
      await prefs.setBool(_isPrivateKey, isPrivate);
    }
    if (optimize != null) {
      await prefs.setBool(_optimizeKey, optimize);
    }
  }
}

final UploadPreferencesStore uploadPreferencesStore = UploadPreferencesStore();
