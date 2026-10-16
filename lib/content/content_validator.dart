import 'package:crypto/crypto.dart';

import '../game_engine/models/level_definition.dart';
import '../game_engine/models/symbol_definition.dart';
import '../game_engine/models/symbol_registry.dart';
import '../game_engine/validation/level_validator.dart';
import 'content_config.dart';
import 'content_exception.dart';
import 'level_manifest.dart';
import 'remote_asset_resolver.dart';

final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
final RegExp _symbolCodePattern = RegExp(r'^[A-Z0-9_]{1,40}$');
final RegExp _colorPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');

/// Checks manifests, registries, levels and bytes before anything is cached
/// as known-good or shown to the player.
class ContentValidator {
  const ContentValidator();

  /// Errors for a manifest. An `incompatible` error means a newer app is
  /// needed; the content itself may be fine.
  List<ValidationIssue> validateManifest(LevelManifest manifest) {
    final errors = <ValidationIssue>[];
    void error(String code, String message) => errors.add(ValidationIssue(code, message));

    if (!kSupportedManifestSchemas.contains(manifest.schemaVersion)) {
      error('unsupported_schema', 'manifest schema ${manifest.schemaVersion} is not supported');
    }
    if (manifest.minClientContentSchema > kClientContentSchema) {
      error(
        'incompatible',
        'content needs client schema ${manifest.minClientContentSchema}, this build has $kClientContentSchema',
      );
    }
    if (ContentVersion.tryParse(manifest.contentVersion) == null) {
      error('invalid_content_version', '"${manifest.contentVersion}" is not a dotted version');
    }
    _checkRef(manifest.symbolRegistry.url, manifest.symbolRegistry.sha256, ContentKind.json, 'symbolRegistry', error);
    if (manifest.levels.isEmpty) error('no_levels', 'manifest lists no levels');
    final ids = <String>{};
    final orders = <int>{};
    for (final level in manifest.levels) {
      if (!ids.add(level.levelId)) error('duplicate_level', 'level ${level.levelId} is listed twice');
      if (!orders.add(level.order)) error('duplicate_order', 'order ${level.order} is used twice');
      _checkRef(level.ref.url, level.ref.sha256, ContentKind.json, level.levelId, error);
    }
    return errors;
  }

  void _checkRef(String url, String? sha, ContentKind kind, String what, void Function(String, String) error) {
    if (!RemoteAssetResolver.isSafe(url, kind)) error('unsafe_path', '$what url "$url" is not a safe content path');
    if (sha != null && !_sha256Pattern.hasMatch(sha)) {
      error('invalid_checksum', '$what sha256 is not 64 lowercase hex characters');
    }
  }

  /// Returns the registry without unusable symbols (unsafe paths, bad
  /// values), each recorded in [SymbolRegistry.rejected], plus registry-level
  /// errors that make the whole registry unusable.
  (SymbolRegistry, List<ValidationIssue>) validateRegistry(SymbolRegistry registry) {
    final errors = <ValidationIssue>[];
    if (!kSupportedRegistrySchemas.contains(registry.schemaVersion)) {
      errors.add(ValidationIssue('unsupported_schema', 'registry schema ${registry.schemaVersion} is not supported'));
    }
    final rejected = <String, String>{};
    for (final symbol in registry.symbols.values) {
      final problem = _symbolProblem(symbol);
      if (problem != null) rejected[symbol.code] = problem;
    }
    final sanitized = registry.without(rejected);
    if (sanitized.symbols.isEmpty) errors.add(const ValidationIssue('no_symbols', 'registry has no usable symbols'));
    return (sanitized, errors);
  }

  String? _symbolProblem(SymbolDefinition symbol) {
    if (!_symbolCodePattern.hasMatch(symbol.code)) return 'code must be A-Z, 0-9 and _';
    if (!_symbolCodePattern.hasMatch(symbol.matchGroup)) return 'matchGroup must be A-Z, 0-9 and _';
    if (symbol.sha256 != null && !_sha256Pattern.hasMatch(symbol.sha256!)) return 'invalid sha256';
    if (symbol.textColor != null && !_colorPattern.hasMatch(symbol.textColor!)) return 'textColor must be #RRGGBB';
    final kind = ContentKind.forSymbol(symbol);
    if (kind != null && !RemoteAssetResolver.isSafe(symbol.assetPath!, kind)) {
      return 'assetPath "${symbol.assetPath}" is not a safe ${kind.name} path';
    }
    return null;
  }

  LevelValidationReport validateLevel(
    LevelDefinition level,
    SymbolRegistry registry, {
    String? expectedLevelId,
    bool checkSolvable = false,
    int solverNodeBudget = 500000,
  }) => LevelValidator(
    registry: registry,
  ).validate(level, expectedLevelId: expectedLevelId, checkSolvable: checkSolvable, solverNodeBudget: solverNodeBudget);

  /// Throws a checksum [ContentException] when [expected] is set and differs.
  static void verifyChecksum(List<int> bytes, String? expected, String path) {
    if (expected == null) return;
    final actual = sha256.convert(bytes).toString();
    if (actual != expected) {
      throw ContentException(ContentErrorKind.checksum, 'expected $expected, got $actual', path: path);
    }
  }
}
