// Shared setup for widget tests and captures of the lobby (home, Levels,
// Settings): offline services on the repository's bundled content, real
// fonts for captures, phone sizes and a pump helper.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/app_update_controller.dart';
import 'package:brain_train/app/play_games_controller.dart';
import 'package:brain_train/app/rewarded_ads_controller.dart';
import 'package:brain_train/app/theme.dart';
import 'package:brain_train/content/asset_download_manager.dart';
import 'package:brain_train/content/content_cache.dart';
import 'package:brain_train/content/content_config.dart';
import 'package:brain_train/content/content_coordinator.dart';
import 'package:brain_train/content/content_fetcher.dart';
import 'package:brain_train/content/content_repositories.dart';
import 'package:brain_train/content/remote_asset_resolver.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/data/settings_repository.dart';
import 'package:brain_train/rendering/symbol_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers.dart';

/// Services on the bundled content with the network unreachable.
Future<AppServices> testServices({
  PlayGamesController? playGames,
  RewardedAdsController? ads,
  AppUpdateController? updates,
}) async {
  final config = ContentConfig(baseUrl: Uri.parse('https://content.test/'), allowedHosts: const {'content.test'});
  final offline = MockClient((r) async => throw http.ClientException('offline', r.url));
  final fetcher = ContentFetcher(client: offline, config: config, delay: (_) async {});
  final cache = ContentCache(MemoryContentStore());
  final resolver = RemoteAssetResolver(config);
  final content = ContentController(
    ContentCoordinator(
      cache: cache,
      bundled: repoContent,
      downloads: AssetDownloadManager(cache: cache, fetcher: fetcher, resolver: resolver),
      manifests: ContentManifestService(fetcher: fetcher, resolver: resolver),
    ),
  );
  await content.start();
  return AppServices(
    content: content,
    progress: await ProgressRepository.open(),
    settings: await SettingsRepository.open(),
    symbolArt: SymbolArtCache(),
    playGames: playGames,
    ads: ads,
    updates: updates,
  );
}

typedef Phone = ({String name, double width, double height, double dpr, double top, double bottom});

const Phone largePhone = (name: '411x914', width: 411, height: 914, dpr: 2.625, top: 24, bottom: 16);
const Phone smallPhone = (name: '360x640', width: 360, height: 640, dpr: 2, top: 24, bottom: 0);
const Phone tallPhone = (name: '430x932', width: 430, height: 932, dpr: 3, top: 47, bottom: 34);

/// Real glyphs instead of test boxes, when the system fonts exist.
Future<void> loadCaptureFonts() async {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/snap/flutter/common/flutter';
  final families = {
    'serif': [
      '/usr/share/fonts/truetype/noto/NotoSerif-Regular.ttf',
      '/usr/share/fonts/truetype/noto/NotoSerif-Bold.ttf',
    ],
    'Roboto': [
      '/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf',
      '/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf',
    ],
    'MaterialIcons': ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'],
  };
  for (final MapEntry(key: family, value: paths) in families.entries) {
    final files = [for (final path in paths) File(path)].where((f) => f.existsSync()).toList();
    if (files.isEmpty) continue;
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();
  }
}

final GlobalKey lobbyBoundary = GlobalKey();

/// Sets the test view to [phone] and pumps [home] in the app's theme.
Future<void> pumpLobby(
  WidgetTester tester, {
  required AppServices services,
  required Widget home,
  Phone phone = largePhone,
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = Size(phone.width * phone.dpr, phone.height * phone.dpr)
    ..devicePixelRatio = phone.dpr
    ..padding = FakeViewPadding(top: phone.top * phone.dpr, bottom: phone.bottom * phone.dpr)
    ..viewPadding = FakeViewPadding(top: phone.top * phone.dpr, bottom: phone.bottom * phone.dpr);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    RepaintBoundary(
      key: lobbyBoundary,
      child: AppScope(
        services: services,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildBrainTrainTheme(), home: home),
      ),
    ),
  );
  await settleLobby(tester);
}

/// Lets images decode and tiles rasterise (real async work), then finishes
/// the hero entrance.
Future<void> settleLobby(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 150));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

/// Writes the current frame to `$CAPTURE_DIR/<name>.png` when set.
Future<void> captureLobby(WidgetTester tester, String name, double dpr) async {
  final dir = Platform.environment['CAPTURE_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary = lobbyBoundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: dpr);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$dir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}
