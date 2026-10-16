/// Highest content schema this build can play. Publishers raise a manifest's
/// `compatibility.minClientContentSchema` above this when content needs new
/// mechanics; older builds then keep their last known-good content.
///
/// - 1: image, emoji and text symbols.
/// - 2: adds `lottie` (animated) symbols. `tool/content.dart build` sets
///   `minClientContentSchema: 2` only when a level uses one, so schema-1
///   builds reject that manifest as a whole instead of installing it with
///   every animated level missing.
/// - 3: trays of 2 or 3 slots and numeric difficulty tiers (`1`..`10`). The
///   build sets 3 when a level uses either, so schema-2 builds keep their
///   known-good content instead of rejecting levels one by one.
const int kClientContentSchema = 3;

/// Asset prefix of the starter pack bundled in the app (levels 1-5, their
/// art, the manifest and the registry); written by `tool/content.dart build`.
const String kStarterContentPrefix = 'content/starter/';

/// Largest Lottie JSON accepted for an animated symbol.
const int kMaxAnimationBytes = 1024 * 1024;

/// Manifest schema versions this build understands.
const Set<int> kSupportedManifestSchemas = {1};

/// Where and how remote content is fetched.
class ContentConfig {
  const ContentConfig({
    required this.baseUrl,
    required this.allowedHosts,
    this.contentRoot = 'brain-train/',
    this.manifestPath = 'manifest.json',
    this.requestTimeout = const Duration(seconds: 12),
    this.maxRetries = 2,
    this.retryBackoff = const Duration(milliseconds: 600),
    this.maxConcurrentDownloads = 8,
    this.maxJsonBytes = 2 * 1024 * 1024,
    this.maxImageBytes = 4 * 1024 * 1024,
    this.maxAnimationBytes = kMaxAnimationBytes,
  });

  /// Public read-only Brain Train content: the `braintrain-public` R2 bucket
  /// on its custom domain, cached at Cloudflare's edge and rate limited per
  /// IP. Builds before versionCode 5 use the `braintrain-assets` Worker on
  /// workers.dev (the private `braintrain` bucket), which keeps serving them.
  static final ContentConfig production = ContentConfig(
    baseUrl: Uri.parse('https://braintrain-cdn.sungamestudio.com/'),
    allowedHosts: const {'braintrain-cdn.sungamestudio.com'},
  );

  final Uri baseUrl;

  /// Hosts content may be loaded from. Anything else is rejected.
  final Set<String> allowedHosts;

  /// Object-key prefix of all game content, with trailing slash.
  final String contentRoot;

  /// Manifest path relative to [contentRoot]. The only mutable object.
  final String manifestPath;

  final Duration requestTimeout;
  final int maxRetries;
  final Duration retryBackoff;
  final int maxConcurrentDownloads;
  final int maxJsonBytes;
  final int maxImageBytes;
  final int maxAnimationBytes;
}
