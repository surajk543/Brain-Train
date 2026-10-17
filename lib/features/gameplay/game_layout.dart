import 'package:flutter/widgets.dart';

import '../../game_engine/campaign/board_shapes.dart';
import '../../rendering/tile_style.dart';
import 'widgets/tray_view.dart';

/// How the gameplay screen shares its height (redesign 1.1.0), top to
/// bottom: [topGap], the HUD ([hudHeight]), the combo timer's row
/// ([timerRow]), the tray, the board (all the rest) and the action bar
/// ([actionBarHeight], then [bottomGap] above the bottom safe area).
///
/// The board must keep the room the campaign was built for: a 360x640 phone
/// gives it at least [kSmallBoardWidth] x [kSmallBoardHeight] (every level's
/// tile faces are then 31 px or wider; `test/content/published_content_test`
/// and `test/features/game_layout_test` check it). So the screen is
/// [compact] (slimmer HUD, smaller tray, action labels beside their buttons)
/// whenever the roomy layout would leave the board less than
/// [kSmallBoardHeight]; the roomy layout puts labels under the buttons like
/// the reference board.
@immutable
class GameLayout {
  const GameLayout._({
    required this.compact,
    required this.topGap,
    required this.hudHeight,
    required this.timerRow,
    required this.trayFaceWidth,
    required this.trayPadV,
    required this.actionBarHeight,
    required this.bottomGap,
  });

  /// The layout for a screen (canvas, on tablets) of [size] with [safe]
  /// insets.
  factory GameLayout.of(Size size, EdgeInsets safe) {
    final roomy = GameLayout._(
      compact: false,
      topGap: 6,
      hudHeight: 56,
      timerRow: 18,
      // Tray tiles: smaller on short screens, so the board keeps its room.
      trayFaceWidth: (size.height * 0.062).clamp(34.0, 46.0),
      trayPadV: TrayLayout.defaultPadV,
      actionBarHeight: 84,
      bottomGap: 6,
    );
    if (roomy.boardHeight(size, safe) >= kSmallBoardHeight) return roomy;
    return const GameLayout._(
      compact: true,
      topGap: 4,
      hudHeight: 46,
      timerRow: 12,
      trayFaceWidth: 34,
      trayPadV: 7,
      actionBarHeight: 44,
      bottomGap: 4,
    );
  }

  /// Short screens (a 360x640 phone): every part is slimmer so the board
  /// keeps its height.
  final bool compact;
  final double topGap;
  final double hudHeight;
  final double timerRow;

  /// Largest tray tile face (narrow screens with a wide tray get less).
  final double trayFaceWidth;
  final double trayPadV;
  final double actionBarHeight;
  final double bottomGap;

  /// Space above and below the HUD row's panel, left and right.
  static const double sideGap = 10;

  /// The tray at its largest.
  double get trayHeight => TrayLayout.heightFor(trayFaceWidth, TileStyle.classicIvory, padV: trayPadV);

  /// Where the HUD ends, from the top of the screen.
  double hudBottom(EdgeInsets safe) => safe.top + topGap + hudHeight;

  /// The board's height on a screen of [size] (at least this: a narrow
  /// screen with a wide tray gets smaller tray tiles, so more).
  double boardHeight(Size size, EdgeInsets safe) =>
      size.height - safe.vertical - topGap - hudHeight - timerRow - trayHeight - actionBarHeight - bottomGap;
}
