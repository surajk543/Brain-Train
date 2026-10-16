import 'dart:convert';
import 'dart:io';

import 'dart:ui';

import 'package:brain_train/content/content_sources.dart';
import 'package:brain_train/game_engine/models/symbol_definition.dart';
import 'package:brain_train/game_engine/models/symbol_registry.dart';
import 'package:brain_train/rendering/mahjong_tile_renderer.dart';
import 'package:brain_train/rendering/symbol_art.dart';
import 'package:brain_train/rendering/tile_style.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  const box = Size(60, 80);

  testWidgets('decodes real WebP symbol art', (tester) async {
    await tester.runAsync(() async {
      // Art of the starter pack (levels 1-5), which the app bundles.
      final symbol = await starterSymbol(SymbolType.image);
      final art = await SymbolArtCache().resolve(symbol, repoContent, box, 2);
      expect(art.isFallback, isFalse);
      expect(art.image.width, 120);
    });
  });

  testWidgets('missing artwork falls back to a drawn face instead of crashing', (tester) async {
    await tester.runAsync(() async {
      const symbol = SymbolDefinition(code: 'GHOST', type: SymbolType.image, assetPath: 'symbols/v9/ghost.webp', label: 'Ghost Leaf');
      final art = await SymbolArtCache().resolve(symbol, repoContent, box, 2);
      expect(art.isFallback, isTrue);
    });
  });

  testWidgets('corrupt image bytes fall back too', (tester) async {
    await tester.runAsync(() async {
      final junk = BundledContentSource((_) async => bytesOf('RIFF0000WEBPnot-really'));
      const symbol = SymbolDefinition(code: 'BAD', type: SymbolType.image, assetPath: 'symbols/v1/bad.webp');
      final art = await SymbolArtCache().resolve(symbol, junk, box, 2);
      expect(art.isFallback, isTrue);
    });
  });

  testWidgets('emoji and text symbols render', (tester) async {
    await tester.runAsync(() async {
      final cache = SymbolArtCache();
      final emoji = await cache.resolve(const SymbolDefinition(code: 'E', type: SymbolType.emoji, value: '🌸'), repoContent, box, 1);
      final text = await cache.resolve(const SymbolDefinition(code: 'T', type: SymbolType.text, value: '發', textColor: '#1E7B3C'), repoContent, box, 1);
      expect(emoji.isFallback || text.isFallback, isFalse);
    });
  });

  testWidgets('tile bodies render once per size with the face inside the image', (tester) async {
    await tester.runAsync(() async {
      final body = await const MahjongTileRenderer(TileStyle.classicIvory).renderBody(const Size(40, 52), 2);
      expect(body.faceOffset.dx, greaterThan(0));
      expect(body.size.width, greaterThan(40));
      expect(body.image.width, (body.size.width * 2).ceil());
      body.dispose();
    });
  });
}

/// A symbol of [type] whose art is in the bundled starter pack.
Future<SymbolDefinition> starterSymbol(SymbolType type) async {
  final manifest = jsonDecode(File('content/starter/manifest.json').readAsStringSync()) as Map<String, Object?>;
  final registry = SymbolRegistry.fromJson(
    jsonDecode(File('content/starter/${(manifest['symbolRegistry']! as Map)['url']}').readAsStringSync()),
  );
  return registry.symbols.values.firstWhere(
    (s) => s.type == type && File('content/starter/${s.assetPath}').existsSync(),
  );
}
