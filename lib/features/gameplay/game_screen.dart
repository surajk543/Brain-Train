import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/brand.dart';
import '../../app/theme.dart';
import '../../content/content_snapshot.dart';
import '../../content/level_manifest.dart';
import '../../data/progress_repository.dart';
import '../../game_engine/models/level_definition.dart';
import '../../game_engine/state/game_state.dart';
import '../../rendering/symbol_art.dart';
import '../levels/level_loader.dart';
import 'game_controller.dart';
import 'widgets/board_intro.dart';
import 'widgets/board_view.dart';
import 'widgets/premium_chrome.dart';
import 'widgets/tile_flight_overlay.dart';
import 'widgets/tile_shatter.dart';
import 'widgets/tray_view.dart';

String formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// The level's first palette colour, used to tint the ambient light.
Color levelAccent(LevelBackdrop? backdrop) {
  final hex = backdrop?.colors.firstOrNull;
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) return BrandGold.warm;
  final value = int.tryParse(hex.substring(1), radix: 16);
  return value == null ? BrandGold.warm : Color(value | 0xFF000000);
}

/// Plays one level from a fixed content snapshot.
///
/// Layout, top to bottom: the matching tray, the board, the HUD. A tapped
/// tile flies from the board to its tray slot in an overlay above both; the
/// result card (win or full tray) appears once the tray has finished its
/// last effect.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.snapshot, required this.entry, this.resume});

  /// Held for the whole game, so content updates cannot change this board.
  final ContentSnapshot snapshot;
  final LevelManifestEntry entry;
  final SavedGame? resume;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  final GlobalKey<BoardViewState> _boardKey = GlobalKey();
  final GlobalKey<TrayViewState> _trayKey = GlobalKey();

  /// Shared by the tray and the flights, so a tile lands on the frame the
  /// tray shows.
  final SymbolAnimationClock _symbolClock = SymbolAnimationClock();

  /// Whether the result card is showing; only the overlay listens.
  final ValueNotifier<bool> _resultShown = ValueNotifier(false);
  GameController? _controller;
  late final TrayController _tray;
  late final TileFlightController _flights;
  final TileShatterController _shatters = TileShatterController();
  final BoardIntroController _intro = BoardIntroController();

  /// The [GameController.introSerial] of the intro started last.
  int _introServed = -1;
  late final TrayFlightDirector _director;
  bool _reduceMotion = false;
  Timer? _resultTimer;

  GameController get controller => _controller!;
  LevelDefinition get level => widget.snapshot.levels[widget.entry.levelId]!;

  static Duration _flightTime(bool reduceMotion) => reduceMotion ? Duration.zero : kTileFlightDuration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_controller == null) {
      final services = AppScope.of(context);
      _reduceMotion = reduceMotion;
      _controller = GameController(
        entry: widget.entry,
        level: level,
        registry: widget.snapshot.registry,
        progress: services.progress,
        settings: services.settings,
        sounds: services.sounds,
        resume: widget.resume,
        // Lose feedback lands with the tile; match and win at the strike.
        arrivalFeedbackDelay: _flightTime(reduceMotion),
        matchFeedbackOnImpact: true,
        winSoundDelay: reduceMotion ? Duration.zero : const Duration(milliseconds: 450),
        // Every game opens with the board intro, unless motion is reduced.
        playIntro: !reduceMotion,
      );
      _tray = TrayController(capacity: controller.trayCapacity);
      _flights = TileFlightController(duration: _flightTime(reduceMotion));
      _director = TrayFlightDirector(
        game: controller,
        tray: _tray,
        flights: _flights,
        boardRect: (id) => _boardKey.currentState?.tileFaceRect(id),
        trayRect: (id) => _trayKey.currentState?.targetRectFor(id),
        hideOnBoard: (ids) => _boardKey.currentState?.hideTiles(ids),
        revealOnBoard: (id) => _boardKey.currentState?.revealTile(id),
        shatters: _shatters,
        snapshotTile: (id) => _trayKey.currentState?.snapshot(id),
        instant: reduceMotion,
      );
      controller
        ..addListener(_syncResult)
        ..addListener(_syncIntro);
      _tray.addListener(_syncResult);
      _flights.addListener(_syncResult);
      _shatters.addListener(_syncResult);
      WidgetsBinding.instance.addObserver(this);
      _syncResult();
    } else if (reduceMotion != _reduceMotion) {
      _reduceMotion = reduceMotion;
      _director.instant = reduceMotion;
      _flights.duration = _flightTime(reduceMotion);
    }
  }

  /// Shows the result card once the game is over and the tray is still:
  /// after the last pair's burst, or after the full tray's shake.
  void _syncResult() {
    if (controller.state.status == GameStatus.playing) {
      _resultTimer?.cancel();
      _resultTimer = null;
      _resultShown.value = false;
      return;
    }
    if (_resultShown.value || _resultTimer != null || _busy) return;
    final delay = _reduceMotion
        ? Duration.zero
        : controller.state.status == GameStatus.trayFull
        ? TrayView.fullDuration
        : const Duration(milliseconds: 250);
    _resultTimer = Timer(delay, () {
      _resultTimer = null;
      if (!mounted || controller.state.status == GameStatus.playing) return;
      // Tray events arrive just after the move: wait for them to play out.
      if (_busy) return;
      _resultShown.value = true;
    });
  }

  /// Starts the board intro when the game wants one (a new game, a restart,
  /// a resumed save) and the board's art is ready; a restart during the
  /// intro starts it again. Only tiles on the board fly; the tray shows its
  /// tiles at once.
  void _syncIntro() {
    if (!controller.introPlaying) {
      _intro.cancel();
      return;
    }
    if (_intro.isRunning && _introServed == controller.introSerial) return;
    final board = _boardKey.currentState;
    if (board == null || !board.hasArt) return; // Retried when the art is in.
    final engine = controller.engine;
    final tiles = [
      for (final index in engine.geometry.drawOrder)
        if (engine.isRemaining(index)) index,
    ];
    final atlas = tiles.isEmpty ? null : board.buildIntroAtlas(tiles);
    if (atlas == null) {
      _intro.cancel();
      controller.endIntro();
      return;
    }
    _introServed = controller.introSerial;
    _intro.play(
      BoardIntro(
        atlas: atlas,
        tiles: tiles,
        layers: [for (final index in tiles) level.tiles[index].layer],
        // The same intro every time a level starts; longer for bigger boards.
        seed: introSeed(level.levelId),
        style: IntroStyle.forLevel(level.levelId),
        duration: IntroTiming.forLevel(
          difficulty: level.difficulty ?? widget.entry.difficulty,
          tileCount: level.tiles.length,
        ),
        geometry: () => _boardKey.currentState?.introGeometry(),
        onLayerLanded: (_) => controller.introLayerLanded(),
        onDone: controller.endIntro,
      ),
    );
  }

  /// A tile is in the air, or the tray or a shatter is still animating.
  bool get _busy => _tray.isBusy || _flights.isFlying || _shatters.isRunning;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      controller.resumeClock();
    } else {
      controller.pauseClock();
    }
  }

  LevelManifestEntry? get _nextEntry {
    final entries = widget.snapshot.playableEntries;
    final index = entries.indexWhere((e) => e.levelId == widget.entry.levelId);
    return index >= 0 && index + 1 < entries.length ? entries[index + 1] : null;
  }

  void _openNext() {
    final next = _nextEntry;
    if (next == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        // Through the loader: the next level may still need downloading.
        builder: (_) => LevelLoaderScreen(entry: next),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resultTimer?.cancel();
    if (_controller != null) {
      controller
        ..removeListener(_syncResult)
        ..removeListener(_syncIntro);
      unawaited(_director.dispose());
      _tray.dispose();
      _flights.dispose();
      _shatters.dispose();
      controller.dispose();
    }
    _intro.dispose();
    _resultShown.dispose();
    _symbolClock.dispose();
    super.dispose();
  }

  /// Tray tiles: smaller on short screens, so the board keeps its room.
  static double _trayFaceWidth(Size screen) => (screen.height * 0.062).clamp(34.0, 46.0);

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Result overlays also dim the status bar area above the tray.
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: kFeltEdge,
      body: EmeraldBackdrop(
        accent: levelAccent(level.backdrop),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The tray sits under the top safe area, the board fills the
            // space down to the HUD, and the HUD pads itself above the
            // bottom inset.
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                                child: TrayView(
                                  key: _trayKey,
                                  controller: _tray,
                                  level: level,
                                  registry: widget.snapshot.registry,
                                  artwork: widget.snapshot.artwork,
                                  symbolArt: services.symbolArt,
                                  reduceMotion: reduceMotion,
                                  maxFaceWidth: _trayFaceWidth(MediaQuery.sizeOf(context)),
                                  symbolClock: _symbolClock,
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 4),
                                  child: RepaintBoundary(
                                    child: BoardView(
                                      key: _boardKey,
                                      controller: controller,
                                      artwork: widget.snapshot.artwork,
                                      symbolArt: services.symbolArt,
                                      dimBlocked: true,
                                      // Follows the phone's accessibility setting.
                                      reduceMotion: reduceMotion,
                                      onArtReady: _syncIntro,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          top: -topInset,
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _resultShown,
                            builder: (context, shown, _) => !shown
                                ? const SizedBox.shrink()
                                : switch (controller.state.status) {
                                    GameStatus.won => _Overlay(
                                      topInset: topInset,
                                      child: _CompletionCard(
                                        controller: controller,
                                        hasNext: _nextEntry != null,
                                        onNext: _openNext,
                                        onReplay: controller.restart,
                                        onLevels: () => Navigator.of(context).pop(),
                                      ),
                                    ),
                                    GameStatus.trayFull => _Overlay(
                                      topInset: topInset,
                                      child: _TrayFullCard(onRevive: controller.revive, onRestart: controller.restart),
                                    ),
                                    GameStatus.playing => const SizedBox.shrink(),
                                  },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(12, 4, 12, 10 + MediaQuery.paddingOf(context).bottom),
                    child: _Hud(entry: widget.entry, controller: controller),
                  ),
                ],
              ),
            ),
            // The board intro: tiles fly in from every side, mix and settle.
            // Ticks only while it runs.
            Positioned.fill(child: BoardIntroOverlay(controller: _intro)),
            // Flying tiles, above the tray, the board and the HUD. Ticks
            // only while a tile is in the air.
            Positioned.fill(
              child: TileFlightOverlay(
                controller: _flights,
                art: () => _boardKey.currentState?.tileArt,
                symbolClock: _symbolClock,
              ),
            ),
            // Matched pairs striking and shattering; shards may fall over
            // the board. Ticks only while a shatter runs.
            Positioned.fill(child: TileShatterOverlay(controller: _shatters)),
          ],
        ),
      ),
    );
  }
}

/// Level name and live statistics. Only the statistics rebuild on moves,
/// and only the clock rebuilds every second.
class _Hud extends StatelessWidget {
  const _Hud({required this.entry, required this.controller});

  final LevelManifestEntry entry;
  final GameController controller;

  @override
  Widget build(BuildContext context) => PremiumHudFrame(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(9, 10, 4, 10),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            PremiumBackButton(onPressed: () => Navigator.of(context).maybePop()),
            const SizedBox(width: 11),
            Expanded(child: _LevelTitle(entry: entry)),
            const SizedBox(width: 4),
            ConstrainedBox(
              // Stats shrink before the title gets too small.
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.47),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) {
                        final state = controller.state;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PremiumStat(label: 'Moves', value: '${state.moveCount}'),
                            const PremiumDivider(),
                            PremiumStat(label: 'Pairs', value: '${state.matchedPairs}/${state.totalPairs}'),
                          ],
                        );
                      },
                    ),
                    const PremiumDivider(),
                    // Ticks every second; keep that repaint to the clock.
                    RepaintBoundary(child: _ClockStat(controller: controller)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LevelTitle extends StatelessWidget {
  const _LevelTitle({required this.entry});

  final LevelManifestEntry entry;

  static const double _titleSize = 22;

  /// Always one line: shrinks the title to fit, down to 62% size, and only
  /// then ellipsizes.
  TextStyle _fit(BuildContext context, double maxWidth) {
    final base = displayText(_titleSize, weight: FontWeight.w500).copyWith(height: 1.12);
    final painter = TextPainter(
      text: TextSpan(text: entry.title, style: base),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    if (width <= maxWidth) return base;
    return base.copyWith(fontSize: _titleSize * math.max(0.62, maxWidth / width * 0.98));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = _fit(context, constraints.maxWidth);
      return Semantics(
        header: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Level ${entry.order}',
                maxLines: 1,
                style: displayText(
                  14 * style.fontSize! / _titleSize,
                  color: BrandGold.base,
                  weight: FontWeight.w500,
                  spacing: 0.4,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(entry.title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: style),
          ],
        ),
      );
    },
  );
}

/// Rebuilds once a second; only this widget, not the board.
class _ClockStat extends StatefulWidget {
  const _ClockStat({required this.controller});

  final GameController controller;

  @override
  State<_ClockStat> createState() => _ClockStatState();
}

class _ClockStatState extends State<_ClockStat> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    // Restart resets the clock at once rather than on the next tick.
    widget.controller.addListener(_tick);
  }

  void _tick() => setState(() {});

  @override
  void dispose() {
    _timer.cancel();
    widget.controller.removeListener(_tick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PremiumStat(label: 'Time', value: formatDuration(widget.controller.elapsed));
}

class _Overlay extends StatelessWidget {
  const _Overlay({required this.topInset, required this.child});

  /// The scrim's strength around the card (it fades from 0x8C to 0x80).
  static const Color _scrim = Color(0x86020D08);

  /// Status bar height the overlay extends under; the card stays centred
  /// over the board below it.
  final double topInset;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    // Covers the board only (the HUD below stays usable), fading out just
    // above the HUD rather than ending at a hard edge.
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x8C020D08), Color(0x80020D08), Color(0x00020D08)],
        stops: [0, 0.92, 1],
      ),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.85, end: 1),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16 + topInset, 16, 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: PremiumPanel(
                    radius: 28,
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                    // The scrim above is between the backdrop and the card.
                    frostTint: _scrim,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _CompletionCard extends StatelessWidget {
  const _CompletionCard({
    required this.controller,
    required this.hasNext,
    required this.onNext,
    required this.onReplay,
    required this.onLevels,
  });

  final GameController controller;
  final bool hasNext;
  final VoidCallback onNext;
  final VoidCallback onReplay;
  final VoidCallback onLevels;

  @override
  Widget build(BuildContext context) {
    final record = controller.winRecord;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const PremiumEmblem(icon: Icons.emoji_events_rounded),
        const SizedBox(height: 12),
        Text(
          'Level complete!',
          textAlign: TextAlign.center,
          style: displayText(28, weight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Text(
          '${controller.state.moveCount} moves  ·  ${formatDuration(controller.elapsed)}',
          textAlign: TextAlign.center,
          style: displayText(17, color: BrainTrainColors.ivory.withValues(alpha: 0.85), weight: FontWeight.w500),
        ),
        if (record != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Best: ${record.bestMoves} moves · ${formatDuration(Duration(milliseconds: record.bestTimeMs))}',
              textAlign: TextAlign.center,
              style: displayText(14, color: BrandGold.base, weight: FontWeight.w500),
            ),
          ),
        const SizedBox(height: 14),
        const PremiumDivider(horizontal: true),
        const SizedBox(height: 16),
        if (hasNext) PremiumButton(label: 'Next level', primary: true, expand: true, onPressed: onNext),
        if (hasNext) const SizedBox(height: 10),
        // The last level: every level is done (owner: say new ones are coming).
        if (!hasNext) ...[
          Text(
            'You have completed every level!\nNew levels are coming soon.',
            textAlign: TextAlign.center,
            style: displayText(16, color: BrandGold.base, weight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
        ],
        PremiumButton(label: 'Replay', primary: !hasNext, expand: true, onPressed: onReplay),
        const SizedBox(height: 4),
        PremiumButton(label: 'Completed Levels', quiet: true, expand: true, onPressed: onLevels),
      ],
    );
  }
}

/// Shown when the tray fills up: revive (the tray's tiles go back to the
/// board) or start the level again. The HUD's Back button stays available.
class _TrayFullCard extends StatelessWidget {
  const _TrayFullCard({required this.onRevive, required this.onRestart});

  final VoidCallback onRevive;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const PremiumEmblem(icon: Icons.inventory_2_outlined),
      const SizedBox(height: 12),
      Text(
        'Tray full',
        textAlign: TextAlign.center,
        style: displayText(28, weight: FontWeight.w600),
      ),
      const SizedBox(height: 10),
      Text(
        'The tray filled up without a match. Revive to put these tiles back on the board, or start again.',
        textAlign: TextAlign.center,
        style: displayText(
          16,
          color: BrainTrainColors.ivory.withValues(alpha: 0.85),
          weight: FontWeight.w400,
        ).copyWith(height: 1.35),
      ),
      const SizedBox(height: 14),
      const PremiumDivider(horizontal: true),
      const SizedBox(height: 16),
      PremiumButton(label: 'Revive', primary: true, expand: true, onPressed: onRevive),
      const SizedBox(height: 10),
      PremiumButton(label: 'Restart', expand: true, onPressed: onRestart),
    ],
  );
}
