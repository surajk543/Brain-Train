import 'dart:async';
import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'analytics.dart';

/// [Analytics] on Google Analytics for Firebase. The only file that imports
/// `firebase_core` and `firebase_analytics`; no call can throw, hang or block
/// the app. The Firebase project comes from the native files
/// (`ios/Runner/GoogleService-Info.plist`, `android/app/google-services.json`);
/// without them [start] fails quietly and nothing is sent. Collection is off
/// at launch (Info.plist and AndroidManifest flags, with every consent type
/// denied and no advertising ID) until [start] has set the consent.
class FirebaseAppAnalytics implements Analytics {
  FirebaseAppAnalytics({this.callTimeout = const Duration(seconds: 10)});

  final Duration callTimeout;

  FirebaseAnalytics? _analytics;
  Future<void>? _starting;
  bool _storage = false;

  @override
  Future<void> start({required bool analyticsStorage}) {
    _storage = analyticsStorage;
    return _starting ??= () async {
      try {
        await Firebase.initializeApp().timeout(callTimeout);
        final analytics = FirebaseAnalytics.instance;
        await _consent(analytics).timeout(callTimeout);
        await analytics.setAnalyticsCollectionEnabled(true).timeout(callTimeout);
        _analytics = analytics;
      } on Object catch (error) {
        debugPrint('Analytics: not started ($error)');
      }
    }();
  }

  @override
  Future<void> setAnalyticsStorage(bool granted) async {
    _storage = granted;
    await _starting;
    final analytics = _analytics;
    if (analytics != null) await _guard(() => _consent(analytics), 'consent');
  }

  @override
  Future<void> event(String name, [Map<String, Object> parameters = const {}]) async {
    await _starting;
    final analytics = _analytics;
    if (analytics != null) await _guard(() => analytics.logEvent(name: name, parameters: parameters), name);
  }

  @override
  Future<void> screen(String name) async {
    await _starting;
    final analytics = _analytics;
    if (analytics != null) await _guard(() => analytics.logScreenView(screenName: name), 'screen $name');
  }

  /// Analytics identifiers only where allowed; never anything for ads.
  Future<void> _consent(FirebaseAnalytics analytics) => analytics.setConsent(
    analyticsStorageConsentGranted: _storage,
    adStorageConsentGranted: false,
    adUserDataConsentGranted: false,
    adPersonalizationSignalsConsentGranted: false,
  );

  Future<void> _guard(Future<void> Function() call, String what) async {
    try {
      await call().timeout(callTimeout);
    } on Object catch (error) {
      debugPrint('Analytics: $what failed ($error)');
    }
  }
}

/// Firebase Analytics on Android and iOS; nothing elsewhere.
Analytics createAnalytics() =>
    Platform.isAndroid || Platform.isIOS ? FirebaseAppAnalytics() : const UnavailableAnalytics();
