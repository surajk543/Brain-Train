import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../content/content_coordinator.dart';
import '../../../content/content_snapshot.dart';
import '../../common/static_layer.dart';

/// A content notice in the lobby ("Offline · playing saved levels ·
/// v2026.10.16.3"), only when something about the content is worth saying.
/// Normal states (checking, up to date) show nothing: no "N levels ready"
/// line (owner).
class LobbyContentFooter extends StatelessWidget {
  const LobbyContentFooter({super.key, required this.snapshot, required this.status});

  final ContentSnapshot snapshot;
  final ContentSyncStatus status;

  /// The notice, or null when there is nothing to say.
  static String? label(ContentSnapshot snapshot, ContentSyncStatus status) {
    final state = switch (status) {
      ContentSyncStatus.updated => 'New content installed',
      ContentSyncStatus.offline => 'Offline · playing saved levels',
      ContentSyncStatus.rejected => 'Update skipped · playing saved levels',
      ContentSyncStatus.checking || ContentSyncStatus.idle || ContentSyncStatus.upToDate => null,
    };
    return state == null ? null : '$state · v${snapshot.contentVersion}';
  }

  @override
  Widget build(BuildContext context) {
    final text = label(snapshot, status);
    if (text == null) return const SizedBox.shrink();
    final lobby = LobbyTheme.of(context);
    return Semantics(
      liveRegion: true,
      // Shadowed text: rendered once, not on every frame of the scene.
      child: StaticLayer(
        overflow: const EdgeInsets.all(6),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: lobby.footerText,
            letterSpacing: 0.3,
            shadows: [Shadow(color: lobby.textShadow, blurRadius: 4, offset: const Offset(0, 1))],
          ),
        ),
      ),
    );
  }
}
