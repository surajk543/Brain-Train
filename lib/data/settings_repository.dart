import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'age_group.dart';

/// Player preferences, persisted and observable.
class SettingsRepository extends ChangeNotifier {
  SettingsRepository(this._prefs);

  static Future<SettingsRepository> open() async => SettingsRepository(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  /// Sound effects on tile picks, matches and wins.
  bool get sound => _prefs.getBool('settings.sound') ?? true;

  /// Vibration (haptic feedback) on tile picks and matches.
  bool get haptics => _prefs.getBool('settings.haptics') ?? true;

  /// From the age screen at first launch; null until it is answered. Kept
  /// on the device only (never sent anywhere).
  AgeGroup? get ageGroup => AgeGroup.parse(_prefs.getString(ageGroupKey));

  static const String ageGroupKey = 'privacy.ageGroup';

  Future<void> setAgeGroup(AgeGroup group) async {
    await _prefs.setString(ageGroupKey, group.storageValue);
    notifyListeners();
  }

  /// True once the first-play tutorial was finished or skipped (or found not
  /// needed: a player who has already won a level). Never reset.
  bool get firstPlayTutorialDone => _prefs.getBool(firstPlayTutorialKey) ?? false;

  static const String firstPlayTutorialKey = 'tutorial.firstPlay.v1';

  /// Not a setting: nothing listens, so it does not notify.
  Future<void> setFirstPlayTutorialDone() async {
    await _prefs.setBool(firstPlayTutorialKey, true);
  }

  Future<void> setSound(bool value) => _setBool('settings.sound', value);
  Future<void> setHaptics(bool value) => _setBool('settings.haptics', value);

  Future<void> _setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
    notifyListeners();
  }
}
