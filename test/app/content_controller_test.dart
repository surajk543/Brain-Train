import 'package:brain_train/app/app_services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../content/fixture_content.dart';

void main() {
  test('keeps retrying until the whole window is on the device (server errors, not only offline)', () async {
    final fixture = FixtureContent(levels: 8);
    // Level 6 enters the window once level 1 is won; the host answers it with
    // 429 (rate limited) until the override is removed.
    final overrides = <String, http.Response>{fixture.levelPaths[6]!: http.Response('busy', 429)};
    final (:coordinator, downloads: _, cache: _) = fixtureCoordinator(
      server: fixture.server(overrides: overrides),
      bundle: fixture.starter(),
      completed: () => {fixture.levelId(1)},
    );
    final controller = ContentController(coordinator, retryDelays: const [Duration(milliseconds: 20)]);
    addTearDown(controller.dispose);

    await controller.start();
    await controller.topUp();
    final level6 = controller.snapshot.manifest.levels.firstWhere((e) => e.order == 6);
    expect(controller.isReady(level6), isFalse);

    overrides.clear();
    for (var i = 0; i < 100 && !controller.isReady(level6); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(controller.isReady(level6), isTrue, reason: 'a retry timer fetched level 6 once the host answered');
  });

  test('retry delays are a few seconds, ending at 30 s', () {
    expect(ContentController.defaultRetryDelays.first, const Duration(seconds: 5));
    expect(ContentController.defaultRetryDelays.last, const Duration(seconds: 30));
  });
}
