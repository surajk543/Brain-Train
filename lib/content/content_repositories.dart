import '../game_engine/models/json_reader.dart';
import '../game_engine/models/level_definition.dart';
import '../game_engine/models/symbol_registry.dart';
import 'content_config.dart';
import 'content_exception.dart';
import 'content_fetcher.dart';
import 'content_sources.dart';
import 'content_validator.dart';
import 'level_manifest.dart';
import 'remote_asset_resolver.dart';

/// Fetches and checks the mutable manifest. Never served from cache: the
/// known-good copy lives in `ContentCache.readKnownGood`.
class ContentManifestService {
  ContentManifestService({required this.fetcher, required this.resolver, this.validator = const ContentValidator()});

  final ContentFetcher fetcher;
  final RemoteAssetResolver resolver;
  final ContentValidator validator;

  /// The remote manifest and its decoded JSON.
  Future<(LevelManifest, Object?)> fetchLatest() async {
    final path = fetcher.config.manifestPath;
    final bytes = await fetcher.get(resolver.manifestUri, maxBytes: fetcher.config.maxJsonBytes, path: path);
    final json = decodeJsonBytes(bytes, path);
    return (parseAndValidate(json, validator, path), json);
  }

  static LevelManifest parseAndValidate(Object? json, ContentValidator validator, String path) {
    final LevelManifest manifest;
    try {
      manifest = LevelManifest.fromJson(json);
    } on JsonFormatException catch (error) {
      throw ContentException(ContentErrorKind.format, error.toString(), path: path);
    }
    final errors = validator.validateManifest(manifest);
    if (errors.any((e) => e.code == 'incompatible')) {
      throw ContentException(ContentErrorKind.incompatible, errors.join('; '), path: path);
    }
    if (errors.isNotEmpty) throw ContentException(ContentErrorKind.validation, errors.join('; '), path: path);
    return manifest;
  }
}

class SymbolRegistryRepository {
  const SymbolRegistryRepository({this.validator = const ContentValidator()});

  final ContentValidator validator;

  /// The registry with unusable symbols moved to `rejected`.
  Future<SymbolRegistry> load(ContentRef ref, ContentSource source) async {
    final bytes = await source.read(ref.url, ContentKind.json, sha256: ref.sha256);
    final SymbolRegistry parsed;
    try {
      parsed = SymbolRegistry.fromJson(decodeJsonBytes(bytes, ref.url));
    } on JsonFormatException catch (error) {
      throw ContentException(ContentErrorKind.format, error.toString(), path: ref.url);
    }
    final (registry, errors) = validator.validateRegistry(parsed);
    if (errors.isNotEmpty) throw ContentException(ContentErrorKind.validation, errors.join('; '), path: ref.url);
    return registry;
  }
}

class LevelRepository {
  const LevelRepository({this.validator = const ContentValidator()});

  final ContentValidator validator;

  /// A level that passed structural, symbol and geometry validation.
  /// Solvability is proven at publish time by `tool/content.dart`.
  Future<LevelDefinition> load(LevelManifestEntry entry, SymbolRegistry registry, ContentSource source) async {
    final bytes = await source.read(entry.ref.url, ContentKind.json, sha256: entry.ref.sha256);
    final LevelDefinition level;
    try {
      level = LevelDefinition.fromJson(decodeJsonBytes(bytes, entry.ref.url));
    } on JsonFormatException catch (error) {
      throw ContentException(ContentErrorKind.format, error.toString(), path: entry.ref.url);
    }
    if (level.schemaVersion > kClientContentSchema) {
      throw ContentException(ContentErrorKind.incompatible, 'level schema ${level.schemaVersion}', path: entry.ref.url);
    }
    final report = validator.validateLevel(level, registry, expectedLevelId: entry.levelId);
    if (!report.isValid) {
      throw ContentException(ContentErrorKind.validation, report.errors.join('; '), path: entry.ref.url);
    }
    return level;
  }
}
