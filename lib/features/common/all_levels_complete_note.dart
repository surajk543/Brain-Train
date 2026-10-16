import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'lobby_chrome.dart';

/// "All levels complete! New levels are coming soon." Shown in the lobby and
/// on Completed Levels once every level is won (owner).
class AllLevelsCompleteNote extends StatelessWidget {
  const AllLevelsCompleteNote({super.key, this.levelCount});

  /// How many levels were won, for the headline; null leaves it out.
  final int? levelCount;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    final title = levelCount == null ? 'All levels complete!' : 'All $levelCount levels complete!';
    return Semantics(
      container: true,
      label: '$title New levels are coming soon.',
      excludeSemantics: true,
      child: LobbyPanel(
        radius: 18,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Icon(Icons.emoji_events_rounded, color: lobby.panelAccent, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: lobbyHeading(context, 17, color: lobby.panelAccent)),
                  const SizedBox(height: 4),
                  Text(
                    'New levels are coming soon. Stay tuned!',
                    style: TextStyle(color: lobby.panelText, fontSize: 13, height: 1.3, letterSpacing: 0.2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
