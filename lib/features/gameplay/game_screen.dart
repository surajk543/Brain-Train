import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/brand.dart';
import '../../app/rewarded_ads_controller.dart';
import '../../app/theme.dart';
import '../../content/content_snapshot.dart';
import '../../content/level_manifest.dart';
import '../../data/progress_repository.dart';
import '../../game_engine/models/level_definition.dart';
import '../../game_engine/state/game_actions.dart';
import '../../game_engine/state/game_engine.dart';
import '../../game_engine/state/game_state.dart';
import '../../rendering/symbol_art.dart';
import '../../rendering/tile_style.dart';
import '../levels/level_loader.dart';
import '../levels/level_select_screen.dart';
import 'game_controller.dart';
import 'game_layout.dart';
import 'widgets/action_bar.dart';
import 'widgets/board_intro.dart';
import 'widgets/board_view.dart';
import 'widgets/combo_badge.dart';
import 'widgets/first_play_tutorial.dart';
import 'widgets/game_hud.dart';
import 'widgets/hint_glow.dart';
import 'widgets/premium_chrome.dart';
import 'widgets/result_cards.dart';
import 'widgets/score_popups.dart';
import 'widgets/tile_flight_overlay.dart';
import 'widgets/tile_shatter.dart';
import 'widgets/tray_view.dart';

export 'widgets/game_hud.dart' show formatDuration;
export 'widgets/result_cards.dart'
    show
        kNoRevivesLeftNote,
        kRefillLoadingNote,
        kRefillOfflineNote,
        kReviveDismissedNote,
        kReviveFreeNote,
        kReviveLoadingNote,
        kReviveOfflineNote,
        refillDismissedNote,
        refillFreeNote;

/// The level's first palette colour, used to tint the ambient light.
Color levelAccent(LevelBackdrop? backdrop) {
  final hex = backdrop?.colors.firstOrNull;
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) return BrandGold.warm;
  final value = int.tryParse(hex.substring(1), radix: 16);
  return value == null ? BrandGold.warm : Color(value | 0xFF000000);
}

/// What a Shuffle that found no new arrangement says (no use is spent).
const String kShuffleFailedNote = 'No new arrangement found. Your shuffle is kept.';

/// Plays one level from a fixed content snapshot.
///
/// Layout (redesign 1.1.0, [GameLayout]), top to bottom: the HUD, the combo
/// timer bar, the matching tray, the board and the action bar (Undo, Hint,
/// Shuffle, Restart). A tapped tile flies from the board to its tray slot in
/// an overlay above both; the result card (win or full tray) appears once
/// the tray has finished its last effect.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.snapshot, required this.entry, this.resume, @visibleForTesting this.stopwatch});

  /// Held for the whole game, so content updates cannot change this board.
  final ContentSnapshot snapshot;
  final LevelManifestEntry entry;
  final SavedGame? resume;

  /// Replaces the game clock's stopwatch (tests drive time by hand).
  final Stopwatch? stopwatch;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  final GlobalKey<BoardViewState> _boardKey = GlobalKey();
  final GlobalKey<TrayViewState> _trayKey = GlobalKey();

  /// Anchors the combo badge to the tray's bottom edge.
  final LayerLink _trayLink = LayerLink();

  /// Shared by the tray and the flights, so a tile lands on the frame the
  /// tray shows.
  final SymbolAnimationClock _symbolClock = SymbolAnimationClock();

  /// Whether the result card is showing; only the overlay listens.
  final ValueNotifier<bool> _resultShown = ValueNotifier(false);

  /// Whether the "Restart this level?" card is open (the clock is paused).
  final ValueNotifier<bool> _confirmingRestart = ValueNotifier(false);

  /// The action whose "Watch an ad for +1 …?" card is open (the clock is
  /// paused), or null.
  final ValueNotifier<GameAction?> _refill = ValueNotifier(null);

  /// A card is open over the board (restart, ad offer): the action bar is
  /// off and Back closes the card.
  final ValueNotifier<bool> _cardOpen = ValueNotifier(false);

  /// The Tray full card's rewarded ad (with its no-ad fallback) while the
  /// card is up and a revive is left; null otherwise.
  RewardedAdOffer? _reviveOffer;

  /// The same for the ad offered for one more Undo, Hint or Shuffle, while
  /// its card is open.
  RewardedAdOffer? _refillOffer;
  late final RewardedAdsController _ads;
  GameController? _controller;
  late final TrayController _tray;
  late final TileFlightController _flights;
  final TileShatterController _shatters = TileShatterController();
  final BoardIntroController _intro = BoardIntroController();

  /// The [GameController.introSerial] of the intro started last.
  int _introServed = -1;

  /// The first-play tutorial while it runs (owner: once per install).
  FirstPlayTutorialController? _tutorial;

  /// Whether to see, once play first begins on this screen, if the tutorial
  /// is due (flag unset, no level won yet).
  bool _tutorialCheck = true;
  late final AppServices _services;
  late final TrayFlightDirector _director;
  bool _reduceMotion = false;
  Timer? _resultTimer;

  /// Set by the first Next Level or Level Select tap: later taps do nothing.
  bool _leaving = false;

  GameController get controller => _controller!;
  LevelDefinition get level => widget.snapshot.levels[widget.entry.levelId]!;

  static Duration _flightTime(bool reduceMotion) => reduceMotion ? Duration.zero : kTileFlightDuration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_controller == null) {
      final services = _services = AppScope.of(context);
      _ads = services.ads;
      // Have an ad ready by the time the tray might fill (never waits).
      _ads.preload();
      _reduceMotion = reduceMotion;
      _controller = GameController(
        entry: widget.entry,
        level: level,
        registry: widget.snapshot.registry,
        progress: services.progress,
        settings: services.settings,
        sounds: services.sounds,
        resume: widget.resume,
        stopwatch: widget.stopwatch,
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
        traySlotRect: (slot) => _trayKey.currentState?.slotRect(slot),
        hideOnBoard: (ids) => _boardKey.currentState?.hideTiles(ids),
        revealOnBoard: (id) => _boardKey.currentState?.revealTile(id),
        shatters: _shatters,
        snapshotTile: (id) => _trayKey.currentState?.snapshot(id),
        instant: reduceMotion,
      );
      controller
        ..addListener(_syncResult)
        ..addListener(_syncIntro)
        ..addListener(_syncTutorial);
      _tray.addListener(_syncResult);
      _flights.addListener(_syncResult);
      _shatters.addListener(_syncResult);
      _confirmingRestart.addListener(_syncCardOpen);
      _refill.addListener(_syncCardOpen);
      WidgetsBinding.instance.addObserver(this);
      _syncResult();
    } else if (reduceMotion != _reduceMotion) {
      _reduceMotion = reduceMotion;
      _director.instant = reduceMotion;
      _flights.duration = _flightTime(reduceMotion);
    }
  }

  void _syncCardOpen() => _cardOpen.value = _confirmingRestart.value || _refill.value != null;

  /// Shows the result card once the game is over and the tray is still:
  /// after the last pair's burst, or after the full tray's shake.
  void _syncResult() {
    if (controller.state.status == GameStatus.playing) {
      _resultTimer?.cancel();
      _resultTimer = null;
      _resultShown.value = false;
      _closeReviveOffer();
      return;
    }
    // The game ended: no card about helpers stays open.
    _closeRefill(resume: false);
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
      // Revive needs an ad: the offer loads one now if none is (retries at
      // once) and counts the fallback wait from here. No revive left: no ad.
      if (controller.state.status == GameStatus.trayFull) {
        _closeReviveOffer();
        if (controller.canRevive) _reviveOffer = _ads.offer();
      }
      _resultShown.value = true;
    });
  }

  void _closeReviveOffer() {
    _reviveOffer?.dispose();
    _reviveOffer = null;
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

  /// The art is in and the intro has handed over (or there is none): the
  /// first time on this screen, the tutorial starts if it is due. Players who
  /// have won a level count as done (installs from before the tutorial).
  void _syncTutorial() {
    if (!_tutorialCheck || controller.introPlaying) return;
    final board = _boardKey.currentState;
    if (board == null || !board.hasArt) return; // Retried when the art is in.
    _tutorialCheck = false;
    final settings = _services.settings;
    if (settings.firstPlayTutorialDone) return;
    if (_services.progress.completed().isNotEmpty) {
      unawaited(settings.setFirstPlayTutorialDone());
      return;
    }
    if (_resultShown.value) return;
    final pair = tutorialPairFor(controller.engine);
    if (pair == null) return; // A resumed game with tiles in the tray: next game.
    final tutorial = FirstPlayTutorialController(
      game: controller,
      pair: pair,
      isBusy: () => _busy,
      motion: Listenable.merge([_tray, _flights, _shatters]),
      onDone: _tutorialDone,
    );
    setState(() => _tutorial = tutorial);
    tutorial.start();
  }

  void _tutorialDone() {
    unawaited(_services.settings.setFirstPlayTutorialDone());
    final tutorial = _tutorial;
    if (tutorial == null || !mounted) return;
    setState(() => _tutorial = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => tutorial.dispose());
  }

  /// A tile is in the air, or the tray or a shatter is still animating.
  bool get _busy => _tray.isBusy || _flights.isFlying || _shatters.isRunning;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The clock stays stopped behind an open card.
      if (!_cardOpen.value) controller.resumeClock();
    } else {
      controller.pauseClock();
    }
  }

  /// Revive from the Tray full card: only after a rewarded ad's reward
  /// (no ad needed in a build without ads), or free when no ad could be had
  /// while online ([RewardedAdOffer]; owner, 2026-10-17). At most
  /// [kMaxRevivesPerLevel] per level attempt, free ones included. The clock
  /// is already stopped (a full tray stops it); the tiles fly back once the
  /// ad has closed and the app is in the foreground again. An ad closed early
  /// leaves the card up, and Revive shows another ad. The offer pays once, so
  /// rapid taps revive once.
  Future<void> _revive() async {
    if (controller.state.status != GameStatus.trayFull || !controller.canRevive) return;
    if (_ads.off) {
      controller.revive();
      return;
    }
    final offer = _reviveOffer;
    if (offer == null || !await offer.claim() || !mounted) return;
    await _untilResumed();
    if (!mounted) return;
    if (controller.state.status == GameStatus.trayFull) controller.revive();
  }

  /// The ad was a separate screen: wait (briefly) for the app to be in the
  /// foreground, so what the reward does is seen.
  static Future<void> _untilResumed() async {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) return;
    final resumed = Completer<void>();
    final listener = AppLifecycleListener(
      onResume: () {
        if (!resumed.isCompleted) resumed.complete();
      },
    );
    try {
      await resumed.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    } finally {
      listener.dispose();
    }
  }

  /// An action bar button: uses [action] when it has a use left; with none
  /// left, offers a rewarded ad for one more (a build without ads grants it
  /// at once, like Revive).
  void _onAction(GameAction action) {
    if (_cardOpen.value || !controller.isAvailable(action)) return;
    if (controller.usesLeft(action) > 0) {
      _use(action);
      return;
    }
    if (_ads.off) {
      controller.grant(action);
      return;
    }
    controller.pauseClock();
    _refillOffer?.dispose();
    // Loads an ad if none is, and counts the fallback wait from this tap.
    _refillOffer = _ads.offer();
    _refill.value = action;
  }

  void _use(GameAction action) {
    switch (action) {
      case GameAction.undo:
        controller.undo();
      case GameAction.hint:
        controller.useHint();
      case GameAction.shuffle:
        final result = controller.shuffle();
        if (result.outcome == ShuffleOutcome.failed && mounted) {
          ScaffoldMessenger.maybeOf(context)
            ?..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text(kShuffleFailedNote)));
        }
    }
  }

  /// "Watch ad" on the ad offer: one more use of the action, granted only
  /// once the reward is earned and the app is in the foreground again, or
  /// ("Get +1 …") free when no ad could be had while online
  /// ([RewardedAdOffer]). An ad closed early grants nothing and leaves the
  /// card up. The clock stays stopped meanwhile (the card stopped it); music
  /// and sound effects are held by the ads controller while the ad shows.
  /// The offer pays once, so rapid taps grant once.
  Future<void> _watchRefillAd() async {
    final action = _refill.value;
    final offer = _refillOffer;
    if (action == null || offer == null || !await offer.claim() || !mounted) return;
    await _untilResumed();
    if (!mounted) return;
    if (_refill.value == action && identical(_refillOffer, offer)) {
      controller.grant(action);
      _closeRefill();
    }
  }

  /// Closes the ad offer (Not now, Back, or a use granted); the clock runs
  /// again unless [resume] is false.
  void _closeRefill({bool resume = true}) {
    if (_refill.value == null) return;
    _refill.value = null;
    _refillOffer?.dispose();
    _refillOffer = null;
    if (resume) controller.resumeClock();
  }

  void _askRestart() {
    controller.pauseClock();
    _confirmingRestart.value = true;
  }

  void _keepPlaying() {
    if (!_confirmingRestart.value) return;
    _confirmingRestart.value = false;
    controller.resumeClock();
  }

  void _confirmRestart() {
    _confirmingRestart.value = false;
    controller.restart();
  }

  /// Android back or the HUD's Back while a card is open: close the card.
  void _closeCard() {
    if (_refill.value != null) {
      if (_refillOffer?.mode != AdOfferMode.busy) _closeRefill();
      return;
    }
    _keepPlaying();
  }

  LevelManifestEntry? get _nextEntry {
    final entries = widget.snapshot.playableEntries;
    final index = entries.indexWhere((e) => e.levelId == widget.entry.levelId);
    return index >= 0 && index + 1 < entries.length ? entries[index + 1] : null;
  }

  void _openNext() {
    final next = _nextEntry;
    if (next == null || _leaving) return;
    _leaving = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        // Through the loader: the next level may still need downloading.
        builder: (_) => LevelLoaderScreen(entry: next),
      ),
    );
  }

  /// Level Select from the win screen: the Levels screen over the lobby
  /// (the game and any Levels screen under it close), so Back from it goes
  /// to the lobby.
  void _openLevelSelect() {
    if (_leaving) return;
    _leaving = true;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LevelSelectScreen()),
      (route) => route.isFirst,
    );
  }

  /// Lobby from the win screen: back to the first route (the lobby), closing
  /// the game and any Levels screen under it.
  void _openLobby() {
    if (_leaving) return;
    _leaving = true;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _replay() {
    if (_leaving || controller.state.status != GameStatus.won) return;
    controller.restart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resultTimer?.cancel();
    if (_controller != null) {
      controller
        ..removeListener(_syncResult)
        ..removeListener(_syncIntro)
        ..removeListener(_syncTutorial);
      _tutorial?.dispose();
      unawaited(_director.dispose());
      _tray.dispose();
      _flights.dispose();
      _shatters.dispose();
      controller.dispose();
    }
    _intro.dispose();
    _resultShown.dispose();
    _confirmingRestart.dispose();
    _refill.dispose();
    _cardOpen.dispose();
    _reviveOffer?.dispose();
    _refillOffer?.dispose();
    _symbolClock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final safe = MediaQuery.paddingOf(context);
    final layout = GameLayout.of(MediaQuery.sizeOf(context), safe);
    // Cards over the board start under the HUD, which stays usable (Back).
    final hudBottom = layout.hudBottom(safe);
    final style = TileStyle.forTileSet(level.tileSetId);
    return Scaffold(
      backgroundColor: BrainTrainPalette.of(context).feltEdge,
      body: EmeraldBackdrop(
        accent: levelAccent(level.backdrop),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // A soft shade under the action bar, so its labels read over the
            // foliage (behind the board and the buttons; static).
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: layout.actionBarHeight + layout.bottomGap + safe.bottom + 28,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        BrainTrainPalette.of(context).feltEdge.withValues(alpha: 0),
                        BrainTrainPalette.of(context).feltEdge.withValues(alpha: 0.62),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Column(
              children: [
                SizedBox(height: safe.top + layout.topGap),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: GameLayout.sideGap),
                  child: SizedBox(
                    height: layout.hudHeight,
                    child: GameHud(
                      entry: widget.entry,
                      controller: controller,
                      compact: layout.compact,
                      onBack: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
                SizedBox(
                  height: layout.timerRow,
                  child: Center(child: ComboTimerBar(controller: controller, compact: layout.compact)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: CompositedTransformTarget(
                    link: _trayLink,
                    child: TrayView(
                      key: _trayKey,
                      controller: _tray,
                      level: level,
                      registry: widget.snapshot.registry,
                      artwork: widget.snapshot.artwork,
                      symbolArt: services.symbolArt,
                      reduceMotion: reduceMotion,
                      maxFaceWidth: layout.trayFaceWidth,
                      padV: layout.trayPadV,
                      symbolClock: _symbolClock,
                      // After a shuffle a tile may show another symbol.
                      symbolOf: controller.symbolCodeOf,
                    ),
                  ),
                ),
                // The board takes every pixel left: its room is what keeps
                // the 31-px tile faces (GameLayout). Nothing else goes
                // between the tray and the board.
                Expanded(
                  child: RepaintBoundary(
                    child: BoardView(
                      key: _boardKey,
                      controller: controller,
                      artwork: widget.snapshot.artwork,
                      symbolArt: services.symbolArt,
                      dimBlocked: true,
                      // Follows the phone's accessibility setting.
                      reduceMotion: reduceMotion,
                      onArtReady: () {
                        _syncIntro();
                        _syncTutorial();
                      },
                    ),
                  ),
                ),
                SizedBox(
                  height: layout.actionBarHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: GameActionBar(
                      controller: controller,
                      ads: _ads,
                      blocked: _cardOpen,
                      compact: layout.compact,
                      disc: layout.actionDisc,
                      onAction: _onAction,
                      onRestart: _askRestart,
                    ),
                  ),
                ),
                SizedBox(height: layout.bottomGap + safe.bottom),
              ],
            ),
            // A hint's gold glow over the board (and its twin in the tray).
            Positioned.fill(
              child: HintGlowOverlay(
                controller: controller,
                tileRect: (id) => _boardKey.currentState?.tileFaceRect(id),
                trayRect: (id) => _trayKey.currentState?.targetRectFor(id),
                style: style,
                reduceMotion: reduceMotion,
              ),
            ),
            // The combo badge hangs on the tray frame's bottom border (a little low, clear of the
            // wells: kComboBadgeAnchor), above the board
            // (a later sibling would hide it) and below the cards, flights, shatters and
            // popups. It takes no space (the board keeps its size: the 31-px face
            // guarantee) and is hidden behind a result or other card.
            Positioned(
              left: 0,
              top: 0,
              child: ListenableBuilder(
                listenable: Listenable.merge([_resultShown, _cardOpen]),
                builder: (context, _) => _resultShown.value || _cardOpen.value
                    ? const SizedBox.shrink()
                    : CompositedTransformFollower(
                        link: _trayLink,
                        showWhenUnlinked: false,
                        targetAnchor: Alignment.bottomCenter,
                        followerAnchor: kComboBadgeAnchor,
                        child: IgnorePointer(
                          child: ComboBadge(controller: controller, reduceMotion: reduceMotion, compact: layout.compact),
                        ),
                      ),
              ),
            ),
            // Result cards: Tray full under the HUD (Back stays), Level
            // Complete over the whole screen.
            ValueListenableBuilder<bool>(
              valueListenable: _resultShown,
              builder: (context, shown, _) => !shown
                  ? const SizedBox.shrink()
                  : switch (controller.state.status) {
                      GameStatus.won => Positioned.fill(
                        child: ResultOverlay(
                          bare: true,
                          topInset: safe.top,
                          // Rebuilds when the async win record lands.
                          child: ListenableBuilder(
                            listenable: controller,
                            builder: (context, _) => LevelCompleteView(
                              controller: controller,
                              compact: layout.compact,
                              hasNext: _nextEntry != null,
                              onNext: _openNext,
                              onLevelSelect: _openLevelSelect,
                              onReplay: _replay,
                              onLobby: _openLobby,
                            ),
                          ),
                        ),
                      ),
                      GameStatus.trayFull => Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        top: hudBottom,
                        child: ResultOverlay(
                          child: TrayFullCard(
                            offer: _reviveOffer,
                            reduceMotion: reduceMotion,
                            onRevive: _revive,
                            onRestart: controller.restart,
                          ),
                        ),
                      ),
                      GameStatus.playing => const SizedBox.shrink(),
                    },
            ),
            // "Restart this level?" and the ad offer for one more Undo, Hint or
            // Shuffle, under the HUD; the HUD's Back closes them (PopScope)
            // instead of leaving, and the action bar is off meanwhile.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              top: hudBottom,
              child: ListenableBuilder(
                listenable: Listenable.merge([_confirmingRestart, _refill]),
                builder: (context, _) {
                  if (_confirmingRestart.value) {
                    return ResultOverlay(
                      child: RestartConfirmCard(onRestart: _confirmRestart, onKeepPlaying: _keepPlaying),
                    );
                  }
                  final action = _refill.value;
                  final offer = _refillOffer;
                  if (action == null || offer == null) return const SizedBox.shrink();
                  return ResultOverlay(
                    child: ActionRefillCard(
                      action: action,
                      offer: offer,
                      reduceMotion: reduceMotion,
                      onWatch: _watchRefillAd,
                      onCancel: _closeRefill,
                    ),
                  );
                },
              ),
            ),
            // Android back closes an open card instead of leaving the game.
            ValueListenableBuilder<bool>(
              valueListenable: _cardOpen,
              builder: (context, open, _) => PopScope(
                canPop: !open,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) _closeCard();
                },
                child: const SizedBox.shrink(),
              ),
            ),
            // The board intro: tiles fly in from every side, mix and settle.
            // Ticks only while it runs.
            Positioned.fill(child: BoardIntroOverlay(controller: _intro)),
            // The first-play tutorial's coach marks: over the board, tray and
            // HUD, under the flights and shatters (they play above its dim).
            if (_tutorial case final tutorial?)
              Positioned.fill(
                child: FirstPlayTutorialOverlay(
                  controller: tutorial,
                  tileRect: (id) => _boardKey.currentState?.tileFaceRect(id),
                  trayRect: () => _trayKey.currentState?.panelRect(),
                  tileStyle: style,
                  reduceMotion: reduceMotion,
                ),
              ),
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
            // Score feedback; ticks only while a popup is alive.
            Positioned.fill(
              child: IgnorePointer(
                child: ScorePopupOverlay(
                  controller: controller,
                  traySlotRect: (slot) => _trayKey.currentState?.slotRect(slot),
                  tileRect: (id) => _boardKey.currentState?.tileFaceRect(id),
                  reduceMotion: reduceMotion,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
