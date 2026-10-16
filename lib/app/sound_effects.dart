import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../data/settings_repository.dart';

enum Sfx {
  /// The player tapped a tile that can be played (it goes to the tray).
  tap('sounds/tap.wav'),
  select('sounds/select.wav'),
  /// Two matched tiles strike each other in the tray (a single hit cut from
  /// the owner's strike.mp3).
  match('sounds/strike.wav'),
  invalid('sounds/invalid.wav'),
  win('sounds/win.wav'),

  /// The tray filled up: the level is lost.
  lose('sounds/lose.wav');

  const Sfx(this.asset);

  /// Path under `assets/` (audioplayers' asset prefix).
  final String asset;
}

/// Short game sound effects, gated by the Sound setting.
///
/// Mixes with other audio instead of taking audio focus, so a player's music
/// keeps playing. Playback problems are swallowed: sound is never allowed to
/// break the game.
class SoundEffects {
  SoundEffects(this.settings);

  final SettingsRepository settings;
  final Map<Sfx, AudioPlayer> _players = {};

  Future<void> preload() async {
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
      );
      for (final sfx in Sfx.values) {
        final player = AudioPlayer();
        await player.setPlayerMode(PlayerMode.lowLatency);
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource(sfx.asset));
        _players[sfx] = player;
      }
    } on Object {
      // No audio available (tests, unusual devices): stay silent.
    }
  }

  void play(Sfx sfx) {
    if (!settings.sound) return;
    final player = _players[sfx];
    if (player == null) return;
    unawaited(() async {
      try {
        await player.stop();
        await player.resume();
      } on Object {
        // Ignore: a missed sound effect is harmless.
      }
    }());
  }

  Future<void> dispose() async {
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
  }
}
