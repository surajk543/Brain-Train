/// App update notice, a small mutable JSON file next to the manifest
/// (`brain-train/app-update.json`; source `content-src/app-update.json`,
/// docs/APP_UPDATES.md):
///
/// ```json
/// {
///   "schemaVersion": 1,
///   "android": { "latestVersionCode": 4, "minVersionCode": 1, "storeUrl": "https://play.google.com/..." },
///   "ios": { "latestBuild": 0, "minBuild": 0, "storeUrl": "" }
/// }
/// ```
///
/// Each platform block may also hold a `message` shown on the lobby card.
/// Unknown fields are ignored; a malformed file or block means no prompt.
library;

import 'dart:convert';

import 'content_exception.dart';
import 'content_fetcher.dart';
import 'content_sources.dart';
import 'remote_asset_resolver.dart';

/// Path of the notice relative to the content root.
const String kAppUpdatePath = 'app-update.json';

/// Notice schema versions this build understands. A file with any other
/// `schemaVersion` is ignored (no prompt).
const Set<int> kSupportedAppUpdateSchemas = {1};

/// Largest notice accepted (it is a few hundred bytes).
const int kMaxAppUpdateBytes = 64 * 1024;

/// Longest `message` shown; longer ones are ignored (the default text shows).
const int kMaxAppUpdateMessageLength = 400;

/// The platforms the notice has a block for.
enum UpdatePlatform {
  android('android', 'latestVersionCode', 'minVersionCode'),
  ios('ios', 'latestBuild', 'minBuild');

  const UpdatePlatform(this.key, this.latestKey, this.minKey);

  /// The block's key in the file.
  final String key;
  final String latestKey;
  final String minKey;
}

/// One platform's block: builds below [minBuild] must update, builds below
/// [latestBuild] may. Build numbers are Android `versionCode`s and iOS
/// `CFBundleVersion`s (the `+N` of the pubspec version).
class PlatformUpdateRule {
  const PlatformUpdateRule({required this.latestBuild, required this.minBuild, this.storeUrl = '', this.message});

  final int latestBuild;
  final int minBuild;

  /// The store page (https), or empty when there is none.
  final String storeUrl;

  /// Shown on the card instead of the default text, when present.
  final String? message;

  /// The block, or null when it is not a usable one (missing or invalid
  /// build numbers). A bad `storeUrl` or `message` is dropped, not fatal.
  static PlatformUpdateRule? tryParse(Object? json, UpdatePlatform platform) {
    if (json is! Map) return null;
    final latest = _build(json[platform.latestKey]);
    final min = _build(json[platform.minKey]);
    if (latest == null || min == null) return null;
    final message = json['message'];
    return PlatformUpdateRule(
      latestBuild: latest,
      minBuild: min,
      storeUrl: _storeUrl(json['storeUrl']),
      message: message is String && message.trim().isNotEmpty && message.trim().length <= kMaxAppUpdateMessageLength
          ? message.trim()
          : null,
    );
  }

  static int? _build(Object? value) {
    if (value is int) return value >= 0 ? value : null;
    // JSON from some editors writes 4.0 for 4.
    if (value is double && value.isFinite && value == value.roundToDouble() && value >= 0) return value.toInt();
    return null;
  }

  static String _storeUrl(Object? value) {
    if (value is! String) return '';
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return '';
    return uri.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is PlatformUpdateRule &&
      other.latestBuild == latestBuild &&
      other.minBuild == minBuild &&
      other.storeUrl == storeUrl &&
      other.message == message;

  @override
  int get hashCode => Object.hash(latestBuild, minBuild, storeUrl, message);
}

/// The parsed notice: a rule per platform, either of which may be missing.
class AppUpdateConfig {
  const AppUpdateConfig({this.android, this.ios});

  final PlatformUpdateRule? android;
  final PlatformUpdateRule? ios;

  PlatformUpdateRule? ruleFor(UpdatePlatform platform) => switch (platform) {
    UpdatePlatform.android => android,
    UpdatePlatform.ios => ios,
  };

  /// The notice, or null when [json] is not one this build understands.
  static AppUpdateConfig? tryParse(Object? json) {
    if (json is! Map) return null;
    final schema = json['schemaVersion'];
    if (schema is! int || !kSupportedAppUpdateSchemas.contains(schema)) return null;
    return AppUpdateConfig(
      android: PlatformUpdateRule.tryParse(json[UpdatePlatform.android.key], UpdatePlatform.android),
      ios: PlatformUpdateRule.tryParse(json[UpdatePlatform.ios.key], UpdatePlatform.ios),
    );
  }

  /// [tryParse] of JSON text (the on-device copy); null when it is not JSON.
  static AppUpdateConfig? tryDecode(String? text) {
    if (text == null) return null;
    try {
      return tryParse(jsonDecode(text));
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) => other is AppUpdateConfig && other.android == android && other.ios == ios;

  @override
  int get hashCode => Object.hash(android, ios);
}

/// What the lobby asks of the player.
enum AppUpdateNeed {
  /// Up to date, or nothing to go by.
  none,

  /// A newer build exists: "Update available", with Later.
  optional,

  /// This build is below the minimum: "Update required", no way past it.
  required,
}

/// The lobby's update card: what is needed, and the platform rule's store
/// page and message.
class AppUpdatePrompt {
  const AppUpdatePrompt(this.need, {this.storeUrl = '', this.message});

  static const AppUpdatePrompt none = AppUpdatePrompt(AppUpdateNeed.none);

  final AppUpdateNeed need;
  final String storeUrl;
  final String? message;

  @override
  bool operator ==(Object other) =>
      other is AppUpdatePrompt && other.need == need && other.storeUrl == storeUrl && other.message == message;

  @override
  int get hashCode => Object.hash(need, storeUrl, message);

  @override
  String toString() => 'AppUpdatePrompt(${need.name})';
}

/// Compares the installed build with [config]'s rule for [platform].
///
/// - below `min`: [AppUpdateNeed.required] (even without a store page: the
///   build is no longer supported);
/// - else below `latest`: [AppUpdateNeed.optional], only with a store page
///   to send the player to;
/// - else, or with no config, platform, rule or build number:
///   [AppUpdateNeed.none].
AppUpdatePrompt decideAppUpdate({
  required AppUpdateConfig? config,
  required UpdatePlatform? platform,
  required int? installedBuild,
}) {
  if (config == null || platform == null || installedBuild == null) return AppUpdatePrompt.none;
  final rule = config.ruleFor(platform);
  if (rule == null) return AppUpdatePrompt.none;
  if (installedBuild < rule.minBuild) {
    return AppUpdatePrompt(AppUpdateNeed.required, storeUrl: rule.storeUrl, message: rule.message);
  }
  if (installedBuild < rule.latestBuild && rule.storeUrl.isNotEmpty) {
    return AppUpdatePrompt(AppUpdateNeed.optional, storeUrl: rule.storeUrl, message: rule.message);
  }
  return AppUpdatePrompt.none;
}

/// How fetching the notice went.
enum AppUpdateFetchStatus {
  /// A notice this build understands ([AppUpdateFetch.config], [AppUpdateFetch.json]).
  found,

  /// The host answered that there is no notice (HTTP 404).
  missing,

  /// The host sent something that is not a usable notice.
  invalid,

  /// No answer (offline, timeout, server trouble).
  failed,
}

class AppUpdateFetch {
  const AppUpdateFetch.found(AppUpdateConfig this.config, String this.json) : status = AppUpdateFetchStatus.found;
  const AppUpdateFetch.missing() : status = AppUpdateFetchStatus.missing, config = null, json = null;
  const AppUpdateFetch.invalid() : status = AppUpdateFetchStatus.invalid, config = null, json = null;
  const AppUpdateFetch.failed() : status = AppUpdateFetchStatus.failed, config = null, json = null;

  final AppUpdateFetchStatus status;
  final AppUpdateConfig? config;

  /// The notice's JSON text, to keep on the device.
  final String? json;
}

/// Fetches the notice from the content host, with the content client's
/// host allow-list, size cap, timeout and retries. Never throws.
class AppUpdateConfigService {
  const AppUpdateConfigService({required this.fetcher, required this.resolver});

  final ContentFetcher fetcher;
  final RemoteAssetResolver resolver;

  Future<AppUpdateFetch> fetch() async {
    try {
      final uri = resolver.resolve(kAppUpdatePath, ContentKind.json);
      final bytes = await fetcher.get(uri, maxBytes: kMaxAppUpdateBytes, path: kAppUpdatePath);
      final json = decodeJsonBytes(bytes, kAppUpdatePath);
      final config = AppUpdateConfig.tryParse(json);
      return config == null ? const AppUpdateFetch.invalid() : AppUpdateFetch.found(config, jsonEncode(json));
    } on ContentException catch (error) {
      return switch (error.kind) {
        ContentErrorKind.notFound => const AppUpdateFetch.missing(),
        ContentErrorKind.format || ContentErrorKind.tooLarge => const AppUpdateFetch.invalid(),
        _ => const AppUpdateFetch.failed(),
      };
    } on Object {
      return const AppUpdateFetch.failed();
    }
  }
}
