import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/play_games_controller.dart';
import 'lobby_buttons.dart';

/// Achievements and Leaderboards (Google Play Games): two small round
/// buttons at the top of the lobby. Nothing without Play Games.
class LobbyPlayGamesButtons extends StatelessWidget {
  const LobbyPlayGamesButtons({super.key, required this.controller, this.size = 48});

  final PlayGamesController controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!controller.available) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LobbyRoundButton(
          key: const ValueKey('lobby-achievements'),
          icon: Icons.military_tech_rounded,
          semanticLabel: 'Achievements',
          size: size,
          onPressed: () => unawaited(controller.openAchievements()),
        ),
        SizedBox(width: size * 0.3),
        LobbyRoundButton(
          key: const ValueKey('lobby-leaderboards'),
          icon: Icons.leaderboard_rounded,
          semanticLabel: 'Leaderboards',
          size: size,
          onPressed: () => unawaited(controller.openLeaderboards()),
        ),
      ],
    );
  }
}
