import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

import '../data/settings_repository.dart';

/// Looping ambient background music ("water flowing").
///
/// Plays at a medium [volume] (the source peaks near 0 dBFS, so full volume
/// would be loud), follows the Sound setting, and pauses while the app is in
/// the background. Playback problems are swallowed: music must never break
/// the game.
class BackgroundMusic with WidgetsBindingObserver {
  BackgroundMusic(this.settings, {this.asset = 'music/water_flowing.mp3', this.volume = 0.6});

  final SettingsRepository settings;

  /// Path under `assets/` (audioplayers' asset prefix).
  final String asset;

  /// 0-1. Medium, not loud.
  final double volume;

  AudioPlayer? _player;
  bool _wanted = false;
  bool _foreground = true;
  bool _interrupted = false;

  /// True while something else plays full screen (a rewarded ad): the music
  /// pauses, and plays again once it is false (Sound and the app's
  /// foreground permitting). On iOS an ad does not take the app out of the
  /// foreground, so this is what silences the music there.
  bool get interrupted => _interrupted;
  set interrupted(bool value) {
    if (value == _interrupted) return;
    _interrupted = value;
    unawaited(_sync());
  }

  /// Starts looping (if Sound is on) and keeps following the Sound setting
  /// and the app lifecycle until [dispose].
  Future<void> start() async {
    if (_wanted) return;
    _wanted = true;
    WidgetsBinding.instance.addObserver(this);
    settings.addListener(_sync);
    try {
      final player = AudioPlayer(playerId: 'background-music');
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(volume);
      await player.setSource(AssetSource(asset));
      _player = player;
    } on Object catch (error) {
      // No audio available: stay silent.
      debugPrint('BackgroundMusic: could not load $asset: $error');
      return;
    }
    await _sync();
  }

  Future<void> _sync() async {
    final player = _player;
    if (player == null) return;
    try {
      if (_wanted && _foreground && !_interrupted && settings.sound) {
        if (player.state != PlayerState.playing) await player.resume();
      } else if (player.state == PlayerState.playing) {
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
    settings.removeListener(_sync);
    await _player?.dispose();
    _player = null;
  }
}
