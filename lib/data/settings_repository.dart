import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Player preferences, persisted and observable.
class SettingsRepository extends ChangeNotifier {
  SettingsRepository(this._prefs);

  static Future<SettingsRepository> open() async => SettingsRepository(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  /// Sound effects on tile picks, matches and wins.
  bool get sound => _prefs.getBool('settings.sound') ?? true;

  /// Vibration (haptic feedback) on tile picks and matches.
  bool get haptics => _prefs.getBool('settings.haptics') ?? true;

  Future<void> setSound(bool value) => _setBool('settings.sound', value);
  Future<void> setHaptics(bool value) => _setBool('settings.haptics', value);

  Future<void> _setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
    notifyListeners();
  }
}
