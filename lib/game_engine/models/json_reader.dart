/// Strict, typed access to decoded JSON.
///
/// Remote content is untrusted, so every accessor checks the runtime type and
/// reports a JSON-path-like location on failure instead of throwing a bare
/// `TypeError` deep inside the game.
library;

/// Thrown when JSON content has the wrong shape or value types.
class JsonFormatException implements Exception {
  JsonFormatException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => 'JsonFormatException at $path: $message';
}

class JsonReader {
  JsonReader(Object? value, [this.path = r'$']) : _map = _asMap(value, path);

  final Map<String, Object?> _map;
  final String path;

  static Map<String, Object?> _asMap(Object? value, String path) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, v) => MapEntry(key.toString(), v));
    }
    throw JsonFormatException(path, 'expected an object');
  }

  Iterable<String> get keys => _map.keys;

  bool has(String key) => _map[key] != null;

  String _at(String key) => '$path.$key';

  Object? _require(String key) {
    final value = _map[key];
    if (value == null) throw JsonFormatException(_at(key), 'is required');
    return value;
  }

  String string(String key) {
    final value = _require(key);
    if (value is! String) throw JsonFormatException(_at(key), 'expected a string');
    return value;
  }

  String? optString(String key) => has(key) ? string(key) : null;

  int integer(String key) {
    final value = _require(key);
    if (value is int) return value;
    if (value is double && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    throw JsonFormatException(_at(key), 'expected an integer');
  }

  int? optInt(String key) => has(key) ? integer(key) : null;

  double number(String key) {
    final value = _require(key);
    if (value is num && value.isFinite) return value.toDouble();
    throw JsonFormatException(_at(key), 'expected a finite number');
  }

  double numberOr(String key, double fallback) =>
      has(key) ? number(key) : fallback;

  bool boolOr(String key, bool fallback) {
    if (!has(key)) return fallback;
    final value = _map[key];
    if (value is! bool) throw JsonFormatException(_at(key), 'expected a boolean');
    return value;
  }

  JsonReader object(String key) => JsonReader(_require(key), _at(key));

  JsonReader? optObject(String key) => has(key) ? object(key) : null;

  List<Object?> _list(String key) {
    final value = _require(key);
    if (value is! List) throw JsonFormatException(_at(key), 'expected an array');
    return value;
  }

  List<JsonReader> objectList(String key) {
    final list = _list(key);
    return [
      for (var i = 0; i < list.length; i++) JsonReader(list[i], '${_at(key)}[$i]'),
    ];
  }

  List<String> stringList(String key) {
    final list = _list(key);
    return [
      for (var i = 0; i < list.length; i++)
        if (list[i] is String)
          list[i] as String
        else
          throw JsonFormatException('${_at(key)}[$i]', 'expected a string'),
    ];
  }

  List<double> numberList(String key) {
    final list = _list(key);
    return [
      for (var i = 0; i < list.length; i++)
        if (list[i] case final num value when value.isFinite)
          value.toDouble()
        else
          throw JsonFormatException('${_at(key)}[$i]', 'expected a finite number'),
    ];
  }

  /// An object whose values are all objects, e.g. the symbol table.
  Map<String, JsonReader> objectMap(String key) {
    final reader = object(key);
    return {
      for (final k in reader.keys) k: JsonReader(reader._map[k], reader._at(k)),
    };
  }

  /// An object whose values are all string arrays, e.g. `matchGroups`.
  Map<String, List<String>> stringListMap(String key) {
    final reader = object(key);
    return {for (final k in reader.keys) k: reader.stringList(k)};
  }

  /// An object whose values are all strings, e.g. `faceColors`.
  Map<String, String> stringMap(String key) {
    final reader = object(key);
    return {for (final k in reader.keys) k: reader.string(k)};
  }
}

/// Writes integral doubles as JSON integers so generated files stay tidy.
num compactNumber(double value) =>
    value == value.roundToDouble() ? value.toInt() : value;
