import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../game_engine/models/level_definition.dart';

const JsonEncoder _pretty = JsonEncoder.withIndent('  ');

/// The published bytes of a level file: indented JSON with one compact line
/// per tile (about half the size of fully indented JSON). Written by
/// `tool/content.dart build`; tests regenerate levels and compare checksums.
String encodeLevelFile(LevelDefinition level) {
  const marker = '__TILES__';
  final json = level.toJson()..['tiles'] = marker;
  final tiles = [for (final tile in level.tiles) '    ${jsonEncode(tile.toJson())}'].join(',\n');
  return '${_pretty.convert(json).replaceFirst('"$marker"', '[\n$tiles\n  ]')}\n';
}

/// `<directory>/<stem>-<first 12 hex of sha256>.json`: the content-addressed
/// key of [text], so changed bytes always get a new key.
String contentAddressedPath(String directory, String stem, String text) =>
    '$directory/$stem-${sha256.convert(utf8.encode(text)).toString().substring(0, 12)}.json';
