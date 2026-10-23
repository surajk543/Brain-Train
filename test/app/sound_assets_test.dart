import 'dart:io';

import 'package:brain_train/app/sound_effects.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every sound effect is bundled, small, and credited in assets/sounds/SOURCES.md', () {
    final sources = File('assets/sounds/SOURCES.md').readAsStringSync();
    for (final sfx in Sfx.values) {
      final file = File('assets/${sfx.asset}');
      expect(file.existsSync(), isTrue, reason: '${sfx.asset} is missing');
      expect(file.lengthSync(), lessThan(200 * 1024), reason: '${sfx.asset} is a short effect');
      expect(sources, contains(file.uri.pathSegments.last), reason: '${sfx.asset} needs a SOURCES.md entry');
    }
    // The music too.
    expect(sources, contains('water_flowing.mp3'));
  });

  test('every file in assets/sounds/ is a sound effect in use', () {
    final used = {for (final sfx in Sfx.values) File('assets/${sfx.asset}').uri.pathSegments.last};
    final bundled = {
      for (final entity in Directory('assets/sounds').listSync())
        if (entity is File && entity.path.endsWith('.wav')) entity.uri.pathSegments.last,
    };
    expect(bundled, used);
  });
}
