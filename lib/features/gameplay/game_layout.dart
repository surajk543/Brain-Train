import 'package:flutter/widgets.dart';

import '../../game_engine/campaign/board_shapes.dart';
import '../../rendering/tile_style.dart';
import 'widgets/tray_view.dart';

/// How the gameplay screen shares its height (redesign 1.1.0), top to
/// bottom: [topGap], the HUD ([hudHeight]), the combo timer's row
/// ([timerRow]), the tray, the board (all the rest) and the action bar
/// ([actionBarHeight], then [bottomGap] above the bottom safe area).
///
/// The board shows the fixed board grid (`boardProjectionFor`), so the tile
/// size grows with the board's height: the tray is low and the action bar
/// one row of round buttons with their labels beside them. A 360x640 phone
/// gives the board at least [kSmallBoardWidth] x [kSmallBoardHeight] (the
/// grid's faces are then 31 px or wider; `test/content/published_content_test`
/// and `test/features/game_layout_test` check it). So the screen is
/// [compact] (slimmer HUD and tray) whenever the roomy layout would leave
/// the board less than [kSmallBoardHeight].
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
    required this.actionDisc,
    required this.bottomGap,
  });

  /// The layout for a screen (canvas, on tablets) of [size] with [safe]
  /// insets.
  factory GameLayout.of(Size size, EdgeInsets safe) {
    // Owner (2026-10-17): a low tray and a compact action bar, so the fixed
    // board grid (boardProjectionFor) gets as much height as possible.
    const roomy = GameLayout._(
      compact: false,
      topGap: 6,
      hudHeight: 56,
      timerRow: 18,
      trayFaceWidth: 32,
      trayPadV: 6,
      actionBarHeight: 50,
      actionDisc: 44,
      bottomGap: 4,
    );
    if (roomy.boardHeight(size, safe) >= kSmallBoardHeight) return roomy;
    return const GameLayout._(
      compact: true,
      topGap: 4,
      hudHeight: 46,
      timerRow: 12,
      trayFaceWidth: 30,
      trayPadV: 5,
      actionBarHeight: 48,
      actionDisc: 44,
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

  /// The action buttons' round discs (labels beside them).
  final double actionDisc;
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
