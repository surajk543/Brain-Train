import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/typography.dart';
import '../../../content/content_coordinator.dart';
import '../../../content/content_snapshot.dart';
import '../../common/static_layer.dart';

/// The lobby's status line (reference: "5 levels ready · v2026.10.16.3"):
/// how many of the next levels to play are on the device right now, and the
/// active content version. A content notice (offline, update skipped, new
/// content installed) takes the place of the level count.
class LobbyContentFooter extends StatelessWidget {
  const LobbyContentFooter({
    super.key,
    required this.snapshot,
    required this.status,
    required this.ready,
    required this.window,
  });

  final ContentSnapshot snapshot;
  final ContentSyncStatus status;

  /// Levels of the window (the next levels to play) on the device, and the
  /// window's size (0 once every level is won).
  final int ready;
  final int window;

  /// The line for [snapshot] in [status] with [ready] of [window] levels on
  /// the device.
  static String label(ContentSnapshot snapshot, ContentSyncStatus status, {required int ready, required int window}) {
    final state = switch (status) {
      ContentSyncStatus.updated => 'New content installed',
      ContentSyncStatus.offline => 'Offline · playing saved levels',
      ContentSyncStatus.rejected => 'Update skipped · playing saved levels',
      ContentSyncStatus.checking || ContentSyncStatus.idle || ContentSyncStatus.upToDate => readyLabel(ready, window),
    };
    final version = 'v${snapshot.contentVersion}';
    return state == null ? version : '$state · $version';
  }

  /// "5 levels ready", "1 level ready", "Getting levels ready" while none is
  /// on the device yet, or null when there is no next level (all won).
  static String? readyLabel(int ready, int window) {
    if (window == 0) return null;
    if (ready == 0) return 'Getting levels ready';
    return ready == 1 ? '1 level ready' : '$ready levels ready';
  }

  @override
  Widget build(BuildContext context) => LobbyNoticeText(label(snapshot, status, ready: ready, window: window));
}

/// One line in the lobby footer's style (content status, Play Games).
class LobbyNoticeText extends StatelessWidget {
  const LobbyNoticeText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    return Semantics(
      liveRegion: true,
      // Shadowed text: rendered once, not on every frame of the scene.
      child: StaticLayer(
        overflow: const EdgeInsets.all(6),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: BrainTrainType.body(size: 13, color: lobby.footerText, weight: FontWeight.w500).copyWith(
            letterSpacing: 0.3,
            shadows: [Shadow(color: lobby.textShadow, blurRadius: 4, offset: const Offset(0, 1))],
          ),
        ),
      ),
    );
  }
}
