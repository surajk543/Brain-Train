/// Usage analytics as the app sees them (owner, 2026-10-24): Google
/// Analytics for Firebase counts players (the Realtime report: who plays
/// now) and a few game events, for everyone and minimally: no advertising
/// identifiers, no ad storage or personalization, never the age group, and
/// in the EEA/UK no analytics identifiers either. Optional and never on the
/// startup path; no call can throw or hang the game. Pure Dart.
library;

abstract class Analytics {
  /// Connects and starts collecting, with analytics identifiers stored only
  /// when [analyticsStorage] (see [setAnalyticsStorage]). Never throws.
  Future<void> start({required bool analyticsStorage});

  /// Whether analytics identifiers (the app instance ID) may be stored:
  /// false where privacy choices are required (EEA/UK), so events go
  /// without one. Ad storage, ad user data and ad personalization are always
  /// denied. Never throws.
  Future<void> setAnalyticsStorage(bool granted);

  /// Logs event [name] with [parameters] (strings and numbers only).
  /// Never throws.
  Future<void> event(String name, [Map<String, Object> parameters = const {}]);

  /// Logs a screen view of [name] ("lobby", "game"). Never throws.
  Future<void> screen(String name);
}

/// No analytics (tests, builds without a Firebase configuration): drops
/// everything.
class UnavailableAnalytics implements Analytics {
  const UnavailableAnalytics();

  @override
  Future<void> start({required bool analyticsStorage}) async {}

  @override
  Future<void> setAnalyticsStorage(bool granted) async {}

  @override
  Future<void> event(String name, [Map<String, Object> parameters = const {}]) async {}

  @override
  Future<void> screen(String name) async {}
}
