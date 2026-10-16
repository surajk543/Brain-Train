import 'json_reader.dart';
import 'symbol_definition.dart';

/// Registry schema versions this build understands.
const Set<int> kSupportedRegistrySchemas = {1};

/// The central table resolving stable symbol codes to renderable artwork.
class SymbolRegistry {
  SymbolRegistry({
    this.schemaVersion = 1,
    required this.registryVersion,
    required Map<String, SymbolDefinition> symbols,
    Map<String, String> rejected = const {},
  }) : symbols = Map.unmodifiable(symbols),
       rejected = Map.unmodifiable(rejected);

  /// Parses a registry. A malformed or unsupported individual symbol is moved
  /// to [rejected] instead of failing the whole registry, so one bad entry
  /// cannot take down every level.
  factory SymbolRegistry.fromJson(Object? decoded) {
    final json = JsonReader(decoded);
    final symbols = <String, SymbolDefinition>{};
    final rejected = <String, String>{};
    for (final entry in json.objectMap('symbols').entries) {
      try {
        symbols[entry.key] = SymbolDefinition.fromJson(entry.key, entry.value);
      } on JsonFormatException catch (error) {
        rejected[entry.key] = error.message;
      }
    }
    return SymbolRegistry(
      schemaVersion: json.integer('schemaVersion'),
      registryVersion: json.string('registryVersion'),
      symbols: symbols,
      rejected: rejected,
    );
  }

  final int schemaVersion;
  final String registryVersion;
  final Map<String, SymbolDefinition> symbols;

  /// Symbol code to the reason it could not be used.
  final Map<String, String> rejected;

  SymbolDefinition? operator [](String code) => symbols[code];

  bool contains(String code) => symbols.containsKey(code);

  /// A copy without the codes in [reasons]; each moves to [rejected].
  SymbolRegistry without(Map<String, String> reasons) => SymbolRegistry(
    schemaVersion: schemaVersion,
    registryVersion: registryVersion,
    symbols: {
      for (final entry in symbols.entries)
        if (!reasons.containsKey(entry.key)) entry.key: entry.value,
    },
    rejected: {...rejected, ...reasons},
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'registryVersion': registryVersion,
    'symbols': {for (final entry in symbols.entries) entry.key: entry.value.toJson()},
  };
}
