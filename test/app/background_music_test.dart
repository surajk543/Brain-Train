// Music is its own setting (redesign 1.1.0): Sound Effects controls only the
// effects, Music only the background music. The music keeps its lifecycle:
// paused in the background and while a rewarded ad shows.
import 'dart:async';

import 'package:brain_train/app/background_music.dart';
import 'package:brain_train/app/rewarded_ads_controller.dart';
import 'package:brain_train/data/settings_repository.dart';
import 'package:brain_train/platform/rewarded_ads.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/fake_rewarded_ads.dart';

/// Records what [BackgroundMusic] asks of its player.
class FakeMusicPlayer implements MusicPlayer {
  String? asset;
  double? volume;
  bool _playing = false;
  int resumes = 0;
  int pauses = 0;
  bool disposed = false;

  @override
  Future<void> load(String asset, double volume) async {
    this.asset = asset;
    this.volume = volume;
  }

  @override
  bool get playing => _playing;

  @override
  Future<void> resume() async {
    resumes++;
    _playing = true;
  }

  @override
  Future<void> pause() async {
    pauses++;
    _playing = false;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Music setting', () {
    test('defaults to on for a new install', () async {
      final settings = await SettingsRepository.open();
      expect(settings.sound, isTrue);
      expect(settings.music, isTrue);
    });

    test('until it is set, Music follows the Sound value stored before 1.1.0 (migration)', () async {
      SharedPreferences.setMockInitialValues({SettingsRepository.soundKey: false});
      final muted = await SettingsRepository.open();
      expect(muted.sound, isFalse);
      expect(muted.music, isFalse, reason: 'a player who muted Sound keeps a silent game');

      SharedPreferences.setMockInitialValues({SettingsRepository.soundKey: true});
      expect((await SettingsRepository.open()).music, isTrue);
    });

    test('Sound Effects and Music are independent, and both persist', () async {
      final settings = await SettingsRepository.open();
      await settings.setSound(false);
      expect(settings.music, isTrue, reason: 'effects off keeps the music');
      await settings.setMusic(false);
      await settings.setSound(true);
      expect(settings.sound, isTrue);
      expect(settings.music, isFalse, reason: 'effects on does not bring the music back');
      final reopened = await SettingsRepository.open();
      expect(reopened.sound, isTrue);
      expect(reopened.music, isFalse);
    });

    test('a migrated, muted player turning Sound Effects on keeps the music off', () async {
      SharedPreferences.setMockInitialValues({SettingsRepository.soundKey: false});
      final settings = await SettingsRepository.open();
      await settings.setSound(true);
      expect(settings.sound, isTrue);
      expect(settings.music, isFalse);
      await settings.setMusic(true);
      expect(settings.music, isTrue);
      expect(settings.sound, isTrue);
    });
  });

  group('BackgroundMusic', () {
    late SettingsRepository settings;
    late FakeMusicPlayer player;
    late BackgroundMusic music;

    setUp(() async {
      settings = await SettingsRepository.open();
      player = FakeMusicPlayer();
      music = BackgroundMusic(settings, player: () => player);
    });

    tearDown(() => music.dispose());

    test('loops the music once started, with Music on', () async {
      expect(player.playing, isFalse, reason: 'nothing before start (after the studio intro)');
      await music.start();
      expect(player.asset, 'music/water_flowing.mp3');
      expect(player.volume, 0.4);
      expect(player.playing, isTrue);
    });

    test('starts silent when Music is off, and plays once it is turned on', () async {
      await settings.setMusic(false);
      await music.start();
      expect(player.playing, isFalse);
      await settings.setMusic(true);
      await pumpEventQueue();
      expect(player.playing, isTrue);
    });

    test('follows Music, not Sound Effects', () async {
      await music.start();
      await settings.setSound(false);
      await pumpEventQueue();
      expect(player.playing, isTrue, reason: 'Sound Effects off');
      await settings.setMusic(false);
      await pumpEventQueue();
      expect(player.playing, isFalse, reason: 'Music off');
      await settings.setSound(true);
      await pumpEventQueue();
      expect(player.playing, isFalse, reason: 'Sound Effects on, Music still off');
      await settings.setMusic(true);
      await pumpEventQueue();
      expect(player.playing, isTrue);
    });

    test('pauses in the background and resumes in the foreground (Music permitting)', () async {
      await music.start();
      music.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await pumpEventQueue();
      expect(player.playing, isFalse);
      music.didChangeAppLifecycleState(AppLifecycleState.paused);
      await pumpEventQueue();
      expect(player.playing, isFalse);
      music.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(player.playing, isTrue);

      // Turned off while in the background: still silent on return.
      music.didChangeAppLifecycleState(AppLifecycleState.paused);
      await settings.setMusic(false);
      music.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(player.playing, isFalse);
    });

    test('is held while a rewarded ad shows, and plays again after it', () async {
      await music.start();
      final ads = FakeRewardedAds()..gate = Completer<void>();
      final controller = RewardedAdsController(ads, music: music);
      addTearDown(controller.dispose);

      final shown = controller.show();
      await pumpEventQueue();
      expect(music.interrupted, isTrue);
      expect(player.playing, isFalse, reason: 'the ad is on screen');
      // The app went to the background and came back while the ad was up.
      music.didChangeAppLifecycleState(AppLifecycleState.paused);
      music.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(player.playing, isFalse, reason: 'still held by the ad');

      ads.gate!.complete();
      expect(await shown, RewardedAdResult.earned);
      await pumpEventQueue();
      expect(music.interrupted, isFalse);
      expect(player.playing, isTrue);
    });

    test('an ad with Music off leaves it off', () async {
      await settings.setMusic(false);
      await music.start();
      music.interrupted = true;
      await pumpEventQueue();
      music.interrupted = false;
      await pumpEventQueue();
      expect(player.playing, isFalse);
      expect(player.resumes, 0);
    });

    test('a player that fails to load stays silent and never throws', () async {
      final failing = BackgroundMusic(settings, player: () => throw StateError('no audio'));
      await failing.start();
      await settings.setMusic(false);
      await settings.setMusic(true);
      await pumpEventQueue();
      await failing.dispose();
    });
  });
}
