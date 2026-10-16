import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../rendering/symbol_art.dart';
import '../game_controller.dart';
import 'tile_art.dart';
import 'tile_shatter.dart';
import 'tray_view.dart';
import '../../../app/tablet_scale.dart';

/// How long a tile takes to fly from the board to its tray slot.
const Duration kTileFlightDuration = Duration(milliseconds: 320);

/// How long a revived tile takes to fly back to the board, landing settle
/// included. Slow on purpose (owner): a revive reads as moves being undone
/// one by one.
const Duration kTileReturnDuration = Duration(milliseconds: 700);

/// Delay between revived tiles taking off: each tile is well on its way
/// before the next one leaves the tray.
const Duration kTileReturnStagger = Duration(milliseconds: 300);

/// How long an undone tile takes to fly back to its board place, settle
/// included: one tile, so quicker than a revive.
const Duration kTileUndoDuration = Duration(milliseconds: 450);

enum FlightKind {
  /// From the board up to a tray slot: rises, then glides across.
  toTray,

  /// From a tray slot back to the board (a revive): glides across, drops
  /// into place and settles with a small squash.
  toBoard,
}

/// One tile in flight between the board and the tray, in global
/// coordinates.
///
/// The target is read again on every frame, so a flight follows its slot if
/// the tray re-packs while it is in the air.
class TileFlight {
  TileFlight._(
    this.tileId,
    this.symbolCode,
    this.from,
    this._target,
    this._onLanded, {
    required this.kind,
    required this.duration,
    required this.delay,
    this._onStart,
  }) : _to = _target() ?? from;

  final String tileId;
  final String symbolCode;

  /// Where the tile's face was when it took off.
  final Rect from;
  final FlightKind kind;

  /// Time in the air, after [delay].
  final Duration duration;

  /// Wait before taking off; the flight is not drawn meanwhile.
  final Duration delay;
  final ValueGetter<Rect?> _target;
  final VoidCallback? _onStart;
  final VoidCallback? _onLanded;
  Rect _to;
  Duration? _launchedAt;
  bool _started = false;
  double _progress = 0;

  /// 0 at take-off, 1 on arrival (linear in time).
  double get progress => _progress;

  /// True once the [delay] is over (the tile is in the air).
  bool get started => _started;

  /// Where the flight ends (the last known target if it went away).
  Rect get to => _to;

  /// The flying tile's face now.
  Rect get rect => kind == FlightKind.toTray ? rectAt(from, _to, _progress) : returnRectAt(from, _to, _progress);

  static Offset _curve(Offset p0, Offset control, Offset p2, double e) {
    final u = 1 - e;
    return p0 * (u * u) + control * (2 * u * e) + p2 * (e * e);
  }

  /// The face at [t] (0-1) of a flight from [from] to [to]: eased, along a
  /// curve that rises first and then glides across into the slot, growing a
  /// little mid-air as if lifted off the board.
  static Rect rectAt(Rect from, Rect to, double t) {
    t = t.clamp(0.0, 1.0);
    final e = Curves.easeInOutCubic.transform(t);
    final p0 = from.center, p2 = to.center;
    final control = Offset.lerp((p0 + p2) / 2, Offset(p0.dx, p2.dy), 0.5)!;
    final lift = 1 + 0.12 * math.sin(math.pi * t);
    final size = Size.lerp(from.size, to.size, e)! * lift;
    return Rect.fromCenter(center: _curve(p0, control, p2, e), width: size.width, height: size.height);
  }

  /// Share of a return flight spent travelling; the rest is the settle.
  static const double returnTravel = 0.8;

  /// The face at [t] (0-1) of a flight back to the board: glides across,
  /// then drops into place (lifted a little mid-air), then settles with a
  /// small squash and ends exactly on [to].
  static Rect returnRectAt(Rect from, Rect to, double t) {
    t = t.clamp(0.0, 1.0);
    if (t >= returnTravel) {
      final s = (t - returnTravel) / (1 - returnTravel);
      final squash = 1 - 0.06 * math.sin(math.pi * s);
      return Rect.fromCenter(center: to.center, width: to.width * squash, height: to.height * squash);
    }
    final travel = t / returnTravel;
    final e = Curves.easeInOutCubic.transform(travel);
    final p0 = from.center, p2 = to.center;
    final control = Offset.lerp((p0 + p2) / 2, Offset(p2.dx, p0.dy), 0.5)!;
    final lift = 1 + 0.1 * math.sin(math.pi * travel);
    final size = Size.lerp(from.size, to.size, e)! * lift;
    return Rect.fromCenter(center: _curve(p0, control, p2, e), width: size.width, height: size.height);
  }
}

/// Runs tile flights. [TileFlightOverlay] ticks it every frame while a
/// flight is pending and draws the tiles; nothing runs otherwise.
class TileFlightController extends ChangeNotifier {
  TileFlightController({this.duration = kTileFlightDuration});

  /// Default flight time. Zero lands tiles at once (reduced motion), even
  /// when a launch asks for its own duration.
  Duration duration;
  final List<TileFlight> _flights = [];

  /// Pending flights, in launch order (later ones are drawn on top).
  List<TileFlight> get flights => UnmodifiableListView(_flights);

  bool get isFlying => _flights.isNotEmpty;

  /// Starts [tileId] flying from [from] towards the rect [to] returns
  /// (global), after [delay]. [onStart] runs when it takes off, [onLanded]
  /// when it arrives. Returns null when the tile landed at once (zero
  /// [duration]): then [onStart] and [onLanded] have both run.
  TileFlight? launch({
    required String tileId,
    required String symbolCode,
    required Rect from,
    required ValueGetter<Rect?> to,
    FlightKind kind = FlightKind.toTray,
    Duration? duration,
    Duration delay = Duration.zero,
    VoidCallback? onStart,
    VoidCallback? onLanded,
  }) {
    if (this.duration <= Duration.zero) {
      onStart?.call();
      onLanded?.call();
      return null;
    }
    final flight = TileFlight._(
      tileId,
      symbolCode,
      from,
      to,
      onLanded,
      kind: kind,
      duration: duration ?? this.duration,
      delay: delay,
      onStart: onStart,
    );
    _flights.add(flight);
    notifyListeners();
    return flight;
  }

  /// Advances every flight to [now] on the driving ticker's clock. A
  /// flight's clock starts at its first tick. Take-offs and landings are
  /// applied first, then their callbacks run.
  void tick(Duration now) {
    if (_flights.isEmpty) return;
    final started = <TileFlight>[], landed = <TileFlight>[];
    for (final flight in _flights) {
      final launched = flight._launchedAt ??= now;
      final airborne = now - launched - flight.delay;
      if (airborne < Duration.zero) continue;
      if (!flight._started) {
        flight._started = true;
        started.add(flight);
      }
      final micros = flight.duration.inMicroseconds;
      flight
        .._progress = micros <= 0 ? 1 : (airborne.inMicroseconds / micros).clamp(0.0, 1.0)
        .._to = flight._target() ?? flight._to;
      if (flight._progress >= 1) landed.add(flight);
    }
    _flights.removeWhere(landed.contains);
    notifyListeners();
    for (final flight in started) {
      flight._onStart?.call();
    }
    for (final flight in landed) {
      flight._onLanded?.call();
    }
  }

  /// Lands every flight now.
  void landAll() {
    final pending = List.of(_flights);
    _flights.clear();
    notifyListeners();
    for (final flight in pending) {
      if (!flight._started) flight._onStart?.call();
      flight._onLanded?.call();
    }
  }

  /// Drops [tileId]'s flight (of [kind], when given) without landing it, and
  /// returns where its tile is drawn now (where it would take off, if it has
  /// not yet); null when it has no such flight.
  Rect? cancel(String tileId, {FlightKind? kind}) {
    final at = _flights.indexWhere((flight) => flight.tileId == tileId && (kind == null || flight.kind == kind));
    if (at < 0) return null;
    final flight = _flights.removeAt(at);
    notifyListeners();
    return flight.started ? flight.rect : flight.from;
  }

  /// Drops every flight without landing it (the level restarted).
  void cancelAll() {
    if (_flights.isEmpty) return;
    _flights.clear();
    notifyListeners();
  }
}

/// Draws flying tiles above the whole gameplay screen.
///
/// Place it over the board and the tray (e.g. last in a full-screen
/// [Stack]); it ignores touches. Its ticker runs only while a flight is in
/// the air, and only it repaints during flights: neither the board nor the
/// tray rebuilds per frame.
class TileFlightOverlay extends StatefulWidget {
  const TileFlightOverlay({super.key, required this.controller, required this.art, this.symbolClock});

  final TileFlightController controller;

  /// Art for the flying tiles, read on every paint (e.g. the board's
  /// `BoardViewState.tileArt`): best at the board's face size, the larger
  /// end of a flight. Null draws nothing; flights still land.
  final ValueGetter<TileArt?> art;

  /// Animates animated symbols in flight (e.g. the tray's clock, so a tile
  /// lands on the frame the tray shows).
  final SymbolAnimationClock? symbolClock;

  @override
  State<TileFlightOverlay> createState() => _TileFlightOverlayState();
}

class _TileFlightOverlayState extends State<TileFlightOverlay> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(widget.controller.tick);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(TileFlightOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      // The ticker calls the first controller's tick; flights are short, so
      // swapping controllers mid-flight is not supported.
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
      _sync();
    }
  }

  void _sync() {
    final flying = widget.controller.isFlying;
    if (flying && !_ticker.isActive) {
      _ticker.start();
    } else if (!flying && _ticker.isActive) {
      _ticker.stop();
    }
  }

  Offset _origin() {
    final box = context.findRenderObject() as RenderBox?;
    return box == null || !box.hasSize ? Offset.zero : box.localToGlobal(Offset.zero, ancestor: TabletScale.canvasAbove(box));
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      size: Size.infinite,
      painter: _FlightPainter(
        controller: widget.controller,
        art: widget.art,
        clock: widget.symbolClock,
        origin: _origin,
      ),
    ),
  );
}

class _FlightPainter extends CustomPainter {
  _FlightPainter({required this.controller, required this.art, required this.clock, required this.origin})
    : super(repaint: controller);

  final TileFlightController controller;
  final ValueGetter<TileArt?> art;
  final SymbolAnimationClock? clock;
  final ValueGetter<Offset> origin;

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.isFlying) return;
    final art = this.art();
    if (art == null) return;
    final shift = -origin();
    final clock = this.clock;
    // Animated symbols replay their vectors here: fine for a short flight.
    final seconds = clock != null && clock.motion ? clock.seconds : null;
    for (final flight in controller.flights) {
      if (!flight.started) continue;
      art.paint(canvas, flight.symbolCode, flight.rect.shift(shift), seconds: seconds);
    }
  }

  @override
  bool shouldRepaint(_FlightPainter old) => old.controller != controller || old.art != art || old.clock != clock;
}

/// Plays game events in the tray: each tile sent to the tray flies from its
/// board face to its tray slot and lands there; once both tiles of a matched
/// pair are in they strike each other and shatter ([shatters], from
/// [snapshotTile] images), with the match feedback at the moment of impact
/// ([GameController.pairImpact]); a full tray shakes once its last tile is
/// in. On a
/// revive the tray's tiles fly back to their board places, one after another,
/// each hidden on the board ([hideOnBoard]) until it lands
/// ([revealOnBoard]), so it is never drawn twice. An undo flies the tile back
/// the same way, from wherever it is (its slot, or mid-flight to it); an
/// undone match's strike is called off and its twin stays in the tray.
///
/// [boardRect] and [trayRect] give global face rects (e.g. the board view's
/// `tileFaceRect` and [TrayViewState.targetRectFor]); [traySlotRect] a slot's
/// ([TrayViewState.slotRect]), for an undone tile whose pair has already
/// gone. When a rect is unknown, or with [instant], tiles move without
/// flying.
class TrayFlightDirector {
  TrayFlightDirector({
    required this.game,
    required this.tray,
    required this.flights,
    required this.boardRect,
    required this.trayRect,
    this.traySlotRect,
    this.hideOnBoard,
    this.revealOnBoard,
    this.shatters,
    this.snapshotTile,
    this.instant = false,
  }) {
    tray
      ..restore(game.state.tray)
      ..onPairReady = _onPairReady;
    _subscription = game.events.listen(handle);
  }

  final GameController game;
  final TrayController tray;
  final TileFlightController flights;
  final Rect? Function(String tileId) boardRect;
  final Rect? Function(String tileId) trayRect;
  final Rect? Function(int slot)? traySlotRect;
  final void Function(Iterable<String> tileIds)? hideOnBoard;
  final void Function(String tileId)? revealOnBoard;

  /// Plays matched pairs striking and shattering; null clears them at once.
  final TileShatterController? shatters;

  /// The tile as it looks in the tray now, as an image (e.g.
  /// [TrayViewState.snapshot]).
  final TileSnapshot? Function(String tileId)? snapshotTile;

  /// Move tiles without flights (reduced motion).
  bool instant;
  late final StreamSubscription<BoardEvent> _subscription;
  late final Map<int, int> _drawRank = {
    for (final (rank, index) in game.engine.geometry.drawOrder.indexed) index: rank,
  };

  /// Running strikes, by both tiles of their pair.
  final Map<String, PairShatter> _strikes = {};

  void handle(BoardEvent event) {
    switch (event) {
      case TileToTray(:final tileId):
        tray.expect(tileId);
        // A tile still flying back to the board takes off again from there.
        final returning = flights.cancel(tileId, kind: FlightKind.toBoard);
        if (returning != null) revealOnBoard?.call(tileId);
        final from = instant ? null : returning ?? boardRect(tileId);
        if (from == null || trayRect(tileId) == null) {
          tray.land(tileId);
          return;
        }
        flights.launch(
          tileId: tileId,
          symbolCode: _symbolOf(tileId),
          from: from,
          to: () => trayRect(tileId),
          onLanded: () => tray.land(tileId),
        );
      case TrayPairCleared(:final tileId, :final partnerId):
        tray.clearPair(partnerId, tileId);
      case TrayFull():
        tray.markFull();
      case TrayReturned(:final tileIds):
        _returnToBoard(tileIds);
      case BoardReset():
        flights.cancelAll();
        shatters?.cancelAll();
        _strikes.clear();
        tray.reset();
      case MoveUndone():
        _takeBack(event);
      case TileRejected() || TileHinted() || BoardShuffled():
        break;
    }
  }

  /// An undo: the tile flies from where it is now (in the air to the tray,
  /// in its slot, or the slot it struck in) back to its board place, hidden
  /// there until it lands; an undone match's strike stops and its twin stays
  /// in the tray.
  void _takeBack(MoveUndone event) {
    final id = event.tileId;
    final inAir = flights.cancel(id, kind: FlightKind.toTray);
    final from = instant ? null : inAir ?? trayRect(id) ?? traySlotRect?.call(event.fromSlot);
    if (event.partnerId case final partner?) {
      final strike = _strikes.remove(id) ?? _strikes.remove(partner);
      _strikes
        ..remove(id)
        ..remove(partner);
      if (strike != null) shatters?.cancel(strike);
    }
    tray.takeBack(id, partnerId: event.partnerId, engineTray: event.tray);
    if (from == null || boardRect(id) == null) {
      revealOnBoard?.call(id);
      return;
    }
    hideOnBoard?.call([id]);
    flights.launch(
      tileId: id,
      symbolCode: _symbolOf(id),
      from: from,
      to: () => boardRect(id),
      kind: FlightKind.toBoard,
      duration: kTileUndoDuration,
      onLanded: () => revealOnBoard?.call(id),
    );
  }

  void _returnToBoard(List<String> tileIds) {
    // Where each tile sits in the tray now, before any slot empties.
    final from = {for (final id in tileIds) id: instant ? null : trayRect(id)};
    tray.returnAll();
    if (from.values.contains(null) || tileIds.any((id) => boardRect(id) == null)) {
      tray.reset();
      return;
    }
    hideOnBoard?.call(tileIds);
    // Lower tiles first, so a tile resting on another lands on top of it.
    final order = [...tileIds]..sort((a, b) => _rankOf(a).compareTo(_rankOf(b)));
    for (final (i, id) in order.indexed) {
      flights.launch(
        tileId: id,
        symbolCode: _symbolOf(id),
        from: from[id]!,
        to: () => boardRect(id),
        kind: FlightKind.toBoard,
        duration: kTileReturnDuration,
        delay: kTileReturnStagger * i,
        onStart: () => tray.depart(id),
        onLanded: () => revealOnBoard?.call(id),
      );
    }
  }

  /// Both tiles of a matched pair are in the tray (or it left without a
  /// strike, [animate] false): strike and shatter, with the match feedback
  /// at impact, then free the slots.
  void _onPairReady(String a, String b, {required bool animate}) {
    if (!animate) {
      game.pairImpact(a, b);
      return;
    }
    final shatters = this.shatters;
    final first = instant || shatters == null ? null : snapshotTile?.call(a);
    final second = first == null || a == b ? null : snapshotTile?.call(b);
    if (shatters == null || first == null || second == null) {
      first?.dispose();
      game.pairImpact(a, b);
      tray.completeClear(a);
      return;
    }
    final strike = shatters.start(
      first,
      second,
      onImpact: () {
        game.pairImpact(a, b);
        tray.impact();
      },
      onDone: () {
        _strikes
          ..remove(a)
          ..remove(b);
        tray.completeClear(a);
      },
    );
    _strikes[a] = strike;
    _strikes[b] = strike;
  }

  int _rankOf(String tileId) => _drawRank[game.engine.indexOf(tileId)] ?? 0;

  /// The symbol the tile shows now (a shuffle may have changed it).
  String _symbolOf(String tileId) => game.symbolCodeOf(tileId);

  Future<void> dispose() {
    if (tray.onPairReady == _onPairReady) tray.onPairReady = null;
    return _subscription.cancel();
  }
}
