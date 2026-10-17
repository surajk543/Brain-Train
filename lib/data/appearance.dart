/// The app's look (owner, 2026-10-17, redesign 1.1.0): Day, Night, or the
/// phone's light / dark setting. Stored on the device (SharedPreferences,
/// `settings.appearance`); new installs follow the system.
enum AppAppearance {
  /// Follows the platform brightness: Day when the phone is light, Night
  /// when it is dark.
  system('system'),

  /// Always the Day look.
  day('day'),

  /// Always the Night look.
  night('night');

  const AppAppearance(this.storageValue);

  /// The value kept in SharedPreferences.
  final String storageValue;

  /// The stored appearance, or null when there is none (or it is unreadable).
  static AppAppearance? tryParse(String? value) {
    for (final appearance in values) {
      if (appearance.storageValue == value) return appearance;
    }
    return null;
  }
}
