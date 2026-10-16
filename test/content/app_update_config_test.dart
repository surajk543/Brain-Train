import 'dart:convert';
import 'dart:io';

import 'package:brain_train/content/app_update_config.dart';
import 'package:brain_train/content/content_config.dart';
import 'package:brain_train/content/content_fetcher.dart';
import 'package:brain_train/content/remote_asset_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _play = 'https://play.google.com/store/apps/details?id=com.sungamestudio.braintrain';

Map<String, Object?> _notice({
  Object? schema = 1,
  Object? android = const {'latestVersionCode': 6, 'minVersionCode': 3, 'storeUrl': _play},
  Object? ios = const {'latestBuild': 0, 'minBuild': 0, 'storeUrl': ''},
}) => {'schemaVersion': schema, 'android': android, 'ios': ios};

AppUpdatePrompt _decide(Object? json, int? build, {UpdatePlatform? platform = UpdatePlatform.android}) =>
    decideAppUpdate(config: AppUpdateConfig.tryParse(json), platform: platform, installedBuild: build);

void main() {
  group('parse', () {
    test('a full notice', () {
      final config = AppUpdateConfig.tryParse(_notice())!;
      expect(config.android, const PlatformUpdateRule(latestBuild: 6, minBuild: 3, storeUrl: _play));
      expect(config.ios, const PlatformUpdateRule(latestBuild: 0, minBuild: 0));
    });

    test('unknown fields are ignored, a message is kept', () {
      final config = AppUpdateConfig.tryParse({
        ..._notice(android: {'latestVersionCode': 6, 'minVersionCode': 3, 'storeUrl': _play, 'message': ' New! ', 'x': 1}),
        'releaseNotes': 'later',
      })!;
      expect(config.android!.message, 'New!');
      expect(config.android!.latestBuild, 6);
    });

    test('malformed JSON text, other shapes and other schemas are no notice', () {
      expect(AppUpdateConfig.tryDecode('{"schemaVersion": 1, "android": '), isNull);
      expect(AppUpdateConfig.tryDecode('<html>Not found</html>'), isNull);
      expect(AppUpdateConfig.tryDecode(null), isNull);
      expect(AppUpdateConfig.tryParse([1, 2]), isNull);
      expect(AppUpdateConfig.tryParse('text'), isNull);
      expect(AppUpdateConfig.tryParse(_notice(schema: 2)), isNull);
      expect(AppUpdateConfig.tryParse(_notice(schema: '1')), isNull);
      expect(AppUpdateConfig.tryParse(_notice(schema: null)), isNull);
    });

    test('a bad platform block is dropped, the other one stays', () {
      for (final bad in <Object?>[
        null,
        'android',
        const {'latestVersionCode': 6},
        const {'latestVersionCode': '6', 'minVersionCode': 3},
        const {'latestVersionCode': 6, 'minVersionCode': -1},
        const {'latestVersionCode': 6.5, 'minVersionCode': 3},
      ]) {
        final config = AppUpdateConfig.tryParse(_notice(android: bad))!;
        expect(config.android, isNull, reason: '$bad');
        expect(config.ios, isNotNull);
      }
    });

    test('4.0 counts as 4; a bad store page or message is dropped, not fatal', () {
      final rule = AppUpdateConfig.tryParse(
        _notice(android: {'latestVersionCode': 4.0, 'minVersionCode': 1, 'storeUrl': 'http://x.test/', 'message': 3}),
      )!.android!;
      expect(rule, const PlatformUpdateRule(latestBuild: 4, minBuild: 1));
      for (final url in ['market://details?id=x', 'javascript:alert(1)', 'not a url', '']) {
        expect(
          AppUpdateConfig.tryParse(_notice(android: {'latestVersionCode': 4, 'minVersionCode': 1, 'storeUrl': url}))!
              .android!
              .storeUrl,
          '',
          reason: url,
        );
      }
      final long = 'x' * (kMaxAppUpdateMessageLength + 1);
      expect(
        AppUpdateConfig.tryParse(_notice(android: {'latestVersionCode': 4, 'minVersionCode': 1, 'message': long}))!
            .android!
            .message,
        isNull,
      );
    });
  });

  group('decide', () {
    test('below min: required; below latest: optional; else none', () {
      expect(_decide(_notice(), 1).need, AppUpdateNeed.required);
      expect(_decide(_notice(), 2).need, AppUpdateNeed.required);
      expect(_decide(_notice(), 3).need, AppUpdateNeed.optional);
      expect(_decide(_notice(), 5).need, AppUpdateNeed.optional);
      expect(_decide(_notice(), 6), AppUpdatePrompt.none);
      expect(_decide(_notice(), 7), AppUpdatePrompt.none);
    });

    test('the prompt carries the store page and message', () {
      final prompt = _decide(
        _notice(android: {'latestVersionCode': 6, 'minVersionCode': 3, 'storeUrl': _play, 'message': 'Hi'}),
        2,
      );
      expect(prompt, const AppUpdatePrompt(AppUpdateNeed.required, storeUrl: _play, message: 'Hi'));
    });

    test('nothing to go by: no config, platform, rule or build number', () {
      expect(_decide(null, 1), AppUpdatePrompt.none);
      expect(_decide('{', 1), AppUpdatePrompt.none);
      expect(_decide(_notice(), null), AppUpdatePrompt.none);
      expect(_decide(_notice(), 1, platform: null), AppUpdatePrompt.none);
      expect(_decide(_notice(android: null), 1), AppUpdatePrompt.none);
      expect(_decide({'schemaVersion': 1}, 1), AppUpdatePrompt.none);
    });

    test('optional needs a store page; required does not', () {
      final noStore = _notice(ios: {'latestBuild': 9, 'minBuild': 0, 'storeUrl': ''});
      expect(_decide(noStore, 4, platform: UpdatePlatform.ios), AppUpdatePrompt.none);
      final forced = _notice(ios: {'latestBuild': 9, 'minBuild': 5, 'storeUrl': ''});
      expect(_decide(forced, 4, platform: UpdatePlatform.ios).need, AppUpdateNeed.required);
    });

    test('platforms have their own rules', () {
      final json = _notice(ios: {'latestBuild': 10, 'minBuild': 8, 'storeUrl': 'https://apps.apple.com/app/id1'});
      expect(_decide(json, 7, platform: UpdatePlatform.ios).need, AppUpdateNeed.required);
      expect(_decide(json, 7, platform: UpdatePlatform.android), AppUpdatePrompt.none);
    });

    test("the repository's notice asks nothing of build 4 (iOS: nothing at all)", () {
      final json = jsonDecode(File('content-src/app-update.json').readAsStringSync());
      final config = AppUpdateConfig.tryParse(json)!;
      expect(config.android!.storeUrl, _play);
      expect(_decide(json, 4), AppUpdatePrompt.none);
      for (final build in [0, 1, 4, 100]) {
        expect(_decide(json, build, platform: UpdatePlatform.ios), AppUpdatePrompt.none);
      }
    });
  });

  group('fetch', () {
    final config = ContentConfig(baseUrl: Uri.parse('https://content.test/'), allowedHosts: const {'content.test'});

    AppUpdateConfigService service(Future<http.Response> Function(http.Request request) handler) {
      final fetcher = ContentFetcher(client: MockClient(handler), config: config, delay: (_) async {});
      return AppUpdateConfigService(fetcher: fetcher, resolver: RemoteAssetResolver(config));
    }

    test('reads brain-train/app-update.json from the content host', () async {
      Uri? asked;
      final fetch = await service((request) async {
        asked = request.url;
        return http.Response(jsonEncode(_notice()), 200);
      }).fetch();
      expect(asked, Uri.parse('https://content.test/brain-train/app-update.json'));
      expect(fetch.status, AppUpdateFetchStatus.found);
      expect(fetch.config, AppUpdateConfig.tryParse(_notice()));
      expect(AppUpdateConfig.tryDecode(fetch.json), fetch.config);
    });

    test('404 is missing; garbage is invalid; no answer is failed', () async {
      expect((await service((_) async => http.Response('', 404)).fetch()).status, AppUpdateFetchStatus.missing);
      expect((await service((_) async => http.Response('{oops', 200)).fetch()).status, AppUpdateFetchStatus.invalid);
      expect(
        (await service((_) async => http.Response(jsonEncode(_notice(schema: 9)), 200)).fetch()).status,
        AppUpdateFetchStatus.invalid,
      );
      expect(
        (await service((_) async => http.Response('x' * (kMaxAppUpdateBytes + 1), 200)).fetch()).status,
        AppUpdateFetchStatus.invalid,
      );
      expect((await service((_) async => http.Response('', 503)).fetch()).status, AppUpdateFetchStatus.failed);
      expect(
        (await service((r) async => throw http.ClientException('offline', r.url)).fetch()).status,
        AppUpdateFetchStatus.failed,
      );
    });

    test('a host outside the allow-list is never asked', () async {
      final elsewhere = ContentConfig(baseUrl: Uri.parse('https://evil.test/'), allowedHosts: const {'content.test'});
      var asked = false;
      final fetcher = ContentFetcher(
        client: MockClient((_) async {
          asked = true;
          return http.Response(jsonEncode(_notice()), 200);
        }),
        config: elsewhere,
      );
      final fetch = await AppUpdateConfigService(fetcher: fetcher, resolver: RemoteAssetResolver(elsewhere)).fetch();
      expect(fetch.status, AppUpdateFetchStatus.failed);
      expect(asked, isFalse);
    });
  });
}
