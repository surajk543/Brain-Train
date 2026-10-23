import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../data/settings_repository.dart';

enum Sfx {
  /// The player tapped a tile that can be played (it goes to the tray): a
  /// soft, tactile click.
  tap('sounds/tap.wav'),

  /// A soft tick: intro layers and revived tiles landing.
  select('sounds/select.wav'),

  /// A tile landed in the tray without a match: a gentle pop with a faint
  /// chime.
  tray('sounds/tray.wav'),

  /// Two matched tiles strike each other in the tray: a rising chime over a
  /// soft whoosh (the shards).
  match('sounds/match.wav'),

  /// A match that continues a combo (x2 and up): a brighter rising chime in
  /// place of [match].
  combo('sounds/combo.wav'),

  /// A blocked tile was tapped: a low, soft thud.
  invalid('sounds/invalid.wav'),

  /// Hint: a crystal bell.
  hint('sounds/hint.wav'),

  /// Undo: a gentle falling swish as the tile flies back.
  undo('sounds/undo.wav'),

  /// Shuffle: a rising sweep with a leafy rustle.
  shuffle('sounds/shuffle.wav'),

  /// The level is won: a short rising fanfare.
  win('sounds/win.wav'),

  /// The tray filled up: the level is lost.
  lose('sounds/lose.wav');

  const Sfx(this.asset);

  /// Path under `assets/` (audioplayers' asset prefix).
  final String asset;
}

/// Short game sound effects, gated by the Sound setting. The files are
/// Kenney CC0 sounds (assets/sounds/SOURCES.md).
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
      await _setAudioContext();
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

  static Future<void> _setAudioContext() => AudioPlayer.global.setAudioContext(
    AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
  );

  /// Applies the game's audio context again (after a rewarded ad, which may
  /// have changed the audio session). Never throws.
  Future<void> restoreAudioContext() async {
    if (_players.isEmpty) return;
    try {
      await _setAudioContext();
    } on Object {
      // Ignore: sound effects are never allowed to break the game.
    }
  }

  /// Stops every sound effect still playing (before a rewarded ad).
  void stopAll() {
    for (final player in _players.values) {
      unawaited(() async {
        try {
          await player.stop();
        } on Object {
          // Ignore.
        }
      }());
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
