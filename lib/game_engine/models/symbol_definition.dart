import 'json_reader.dart';

/// Renderer types this build can draw. A registry entry of any other type is
/// rejected (not fatal): levels that use it fail validation instead.
enum SymbolType {
  image,
  emoji,
  text,

  /// Animated artwork: a Lottie JSON file at `assetPath`
  /// (e.g. `animated-symbols/emoji-01.json`). Needs client content schema 2.
  lottie;

  static SymbolType? fromWire(String value) {
    for (final type in values) {
      if (type.name == value) return type;
    }
    return null;
  }
}

/// One entry of the symbol registry. Identity is [code]; artwork is data.
class SymbolDefinition {
  const SymbolDefinition({
    required this.code,
    required this.type,
    this.assetPath,
    this.value,
    String? matchGroup,
    this.label,
    this.sha256,
    this.isPlaceholder = false,
    this.sourceUrl,
    this.textColor,
  }) : matchGroup = matchGroup ?? code;

  factory SymbolDefinition.fromJson(String code, JsonReader json) {
    final typeWire = json.string('type');
    final type = SymbolType.fromWire(typeWire);
    if (type == null) {
      throw JsonFormatException('${json.path}.type', 'unsupported symbol type "$typeWire"');
    }
    final definition = SymbolDefinition(
      code: code,
      type: type,
      assetPath: json.optString('assetPath'),
      value: json.optString('value'),
      matchGroup: json.optString('matchGroup'),
      label: json.optString('label'),
      sha256: json.optString('sha256'),
      isPlaceholder: json.boolOr('placeholder', false),
      sourceUrl: json.optString('source'),
      textColor: json.optString('textColor'),
    );
    switch (type) {
      case SymbolType.image:
      case SymbolType.lottie:
        if (definition.assetPath == null || definition.assetPath!.isEmpty) {
          throw JsonFormatException('${json.path}.assetPath', '${type.name} symbols need an assetPath');
        }
      case SymbolType.emoji:
      case SymbolType.text:
        final value = definition.value;
        if (value == null || value.isEmpty || value.length > 12) {
          throw JsonFormatException('${json.path}.value', '${type.name} symbols need a 1-12 character value');
        }
    }
    return definition;
  }

  final String code;
  final SymbolType type;

  /// Content-root-relative path of the artwork, e.g. `symbols/v1/leaf-01.webp`
  /// or, for [SymbolType.lottie], `animated-symbols/emoji-01.json`.
  final String? assetPath;

  /// Glyphs for [SymbolType.emoji] and [SymbolType.text].
  final String? value;

  /// Symbols with equal match groups match under `match_group` levels.
  final String matchGroup;

  /// Human-readable name, used for accessibility and the fallback face.
  final String? label;

  /// Optional lowercase hex SHA-256 of the artwork bytes.
  final String? sha256;

  /// True while the artwork is a stand-in for the licensed original.
  final bool isPlaceholder;

  /// Where the original artwork came from. Informational; never fetched.
  final String? sourceUrl;

  /// `#RRGGBB` colour for text symbols.
  final String? textColor;

  String get displayName => label ?? code;

  /// True for symbols whose artwork is an animation.
  bool get isAnimated => type == SymbolType.lottie;

  Map<String, Object?> toJson() => {
    'type': type.name,
    if (assetPath != null) 'assetPath': assetPath,
    if (value != null) 'value': value,
    'matchGroup': matchGroup,
    if (label != null) 'label': label,
    if (sha256 != null) 'sha256': sha256,
    if (isPlaceholder) 'placeholder': true,
    if (sourceUrl != null) 'source': sourceUrl,
    if (textColor != null) 'textColor': textColor,
  };
}
