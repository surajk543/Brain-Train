import 'package:brain_train/platform/analytics.dart';

/// Records what would go to Firebase, in order.
class FakeAnalytics implements Analytics {
  final calls = <String>[];
  final events = <(String, Map<String, Object>)>[];

  @override
  Future<void> start({required bool analyticsStorage}) async => calls.add('start storage=$analyticsStorage');

  @override
  Future<void> setAnalyticsStorage(bool granted) async => calls.add('storage=$granted');

  @override
  Future<void> event(String name, [Map<String, Object> parameters = const {}]) async {
    calls.add('event $name');
    events.add((name, parameters));
  }

  @override
  Future<void> screen(String name) async => calls.add('screen $name');
}
