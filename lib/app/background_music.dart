import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

import '../data/settings_repository.dart';

/// The looping player behind [BackgroundMusic]: audioplayers in the app, a
/// fake in tests.
abstract class MusicPlayer {
  /// Loads [asset] (a path under `assets/`) to loop at [volume] (0-1).
  Future<void> load(String asset, double volume);

  bool get playing;
  Future<void> resume();
  Future<void> pause();
  Future<void> dispose();
}

class _AudioplayersMusic implements MusicPlayer {
  final AudioPlayer _player = AudioPlayer(playerId: 'background-music');

  @override
  Future<void> load(String asset, double volume) async {
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(volume);
    await _player.setSource(AssetSource(asset));
  }

  @override
  bool get playing => _player.state == PlayerState.playing;

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> dispose() => _player.dispose();
}

/// Looping ambient background music ("water flowing").
///
/// Plays at a medium [volume] (the source peaks near 0 dBFS, so full volume
/// would be loud), follows the Music setting (redesign 1.1.0; Sound Effects
/// no longer affects it), and pauses while the app is in the background and
/// while a rewarded ad is on screen ([interrupted]). Playback problems are
/// swallowed: music must never break the game.
class BackgroundMusic with WidgetsBindingObserver {
  BackgroundMusic(
    this.settings, {
    this.asset = 'music/water_flowing.mp3',
    this.volume = 0.6,
    MusicPlayer Function()? player,
  }) : _createPlayer = player ?? _AudioplayersMusic.new;

  final SettingsRepository settings;

  /// Path under `assets/` (audioplayers' asset prefix).
  final String asset;

  /// 0-1. Medium, not loud.
  final double volume;

  final MusicPlayer Function() _createPlayer;
  MusicPlayer? _player;
  bool _wanted = false;
  bool _foreground = true;
  bool _interrupted = false;

  /// True while something else plays full screen (a rewarded ad): the music
  /// pauses, and plays again once it is false (Music and the app's
  /// foreground permitting). On iOS an ad does not take the app out of the
  /// foreground, so this is what silences the music there.
  bool get interrupted => _interrupted;
  set interrupted(bool value) {
    if (value == _interrupted) return;
    _interrupted = value;
    unawaited(_sync());
  }

  /// Whether the music should be playing now: started, the app in the
  /// foreground, no ad on screen and Music on.
  bool get audible => _wanted && _foreground && !_interrupted && settings.music;

  /// Starts looping (if Music is on) and keeps following the Music setting
  /// and the app lifecycle until [dispose].
  Future<void> start() async {
    if (_wanted) return;
    _wanted = true;
    WidgetsBinding.instance.addObserver(this);
    settings.addListener(_settingsChanged);
    try {
      final player = _createPlayer();
      await player.load(asset, volume);
      _player = player;
    } on Object catch (error) {
      // No audio available: stay silent.
      debugPrint('BackgroundMusic: could not load $asset: $error');
      return;
    }
    await _sync();
  }

  void _settingsChanged() => unawaited(_sync());

  Future<void> _sync() async {
    final player = _player;
    if (player == null) return;
    try {
      if (audible) {
        if (!player.playing) await player.resume();
      } else if (player.playing) {
        await player.pause();
      }
    } on Object catch (error) {
      // Ignore: a missed play/pause is harmless.
      debugPrint('BackgroundMusic: play/pause failed: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    unawaited(_sync());
  }

  Future<void> dispose() async {
    _wanted = false;
    WidgetsBinding.instance.removeObserver(this);
    settings.removeListener(_settingsChanged);
    await _player?.dispose();
    _player = null;
  }
}
