import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'age_group.dart';

/// Player preferences, persisted and observable.
class SettingsRepository extends ChangeNotifier {
  SettingsRepository(this._prefs);

  static Future<SettingsRepository> open() async => SettingsRepository(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  /// Sound effects on tile picks, matches and wins ("Sound Effects"). Only
  /// the effects: the background music has its own switch ([music]).
  bool get sound => _prefs.getBool(soundKey) ?? true;

  static const String soundKey = 'settings.sound';

  /// Background music (redesign 1.1.0: its own switch, separate from Sound
  /// Effects). Before 1.1.0 the Sound switch also silenced the music, so
  /// until Music is set it follows the stored Sound value: a player who had
  /// muted Sound keeps a silent game.
  bool get music => _prefs.getBool(musicKey) ?? sound;

  static const String musicKey = 'settings.music';

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

  Future<void> setSound(bool value) async {
    // Music stops following Sound the first time Sound changes: it keeps
    // the value it had (see [music]).
    if (!_prefs.containsKey(musicKey)) await _prefs.setBool(musicKey, music);
    await _setBool(soundKey, value);
  }

  Future<void> setMusic(bool value) => _setBool(musicKey, value);
  Future<void> setHaptics(bool value) => _setBool('settings.haptics', value);

  Future<void> _setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
    notifyListeners();
  }
}
