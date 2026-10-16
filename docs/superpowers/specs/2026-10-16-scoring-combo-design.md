# Scoring and combo system — design

Date: 2026-10-16 · Branch: `feat/play-games` · Status: design approved section by section, awaiting spec review

## Goal

Every matched pair earns points; fast consecutive matches build a combo with a multiplier and a speed bonus. Score and
combo show live during play, on the Level complete card and in Completed Levels, and the best score and best combo
per level are stored. Later, Play Games piece 2 builds a total-score leaderboard and combo achievements on these
records.

### Owner decisions (2026-10-16)

- Purpose: **personal bests + Play Games leaderboards** (piece 2 reads the stored bests).
- Bottom bar: **SCORE replaces MOVES**; Moves move to the win card. A **combo badge** sits between the tray and the
  board, with the best combo under it.
- **Revive ends the active combo; the score and best combo are kept**; Revive stays free and unlimited.
- Architecture **A**: a pure-Dart `ScoreKeeper` fed by `GameController`.
- **Tapping a blocked tile costs 1 point and ends the active combo; the score never goes below 0** (owner: "tapping
  an incorrect tile reduces the score by 1 … but don't make the score negative").
- Undo, Hint and Shuffle do not exist (CLAUDE.md: "Restart is the only action"): nothing to reverse, nothing shown
  for them.
- All work stays on `feat/play-games`.

## 1. Rules and timing

`ScoringRules` (pure Dart, `lib/game_engine/scoring/scoring_rules.dart`), all values configurable:

| Value | Default |
|---|---|
| `basePoints` | 100 |
| `comboWindow` | 3 s |
| `maxMultiplier` | 5 |
| speed tiers | gap < 1 s → +50; 1 s ≤ gap < 2 s → +25; 2 s ≤ gap ≤ 3 s → +10 |
| `blockedTapPenalty` | 1 |

`ScoreKeeper` (`lib/game_engine/scoring/score_keeper.dart`) holds `score`, `currentCombo`, `bestCombo`,
`currentMultiplier`, `lastSuccessfulMatchTime`, `comboExpiresAt`, `speedBonus` (of the last match),
`totalPairsMatched`.

`MatchScore onMatch(Duration t)` — called once per confirmed match with the game-clock time `t`:

1. `gap = t − lastSuccessfulMatchTime` (none for the first match).
2. If there is no previous match, or `gap > comboWindow`: the streak restarts — `currentCombo = 1`, `speedBonus = 0`.
3. Else (`gap ≤ comboWindow`, 3.000 s included): `currentCombo += 1`, `speedBonus` from the tier of `gap`.
4. `currentMultiplier = min(currentCombo, maxMultiplier)` — the visible streak may exceed 5, the multiplier does not.
5. `earned = basePoints × currentMultiplier + speedBonus`; `score += earned`; `bestCombo = max(bestCombo,
   currentCombo)`; `totalPairsMatched += 1`; `lastSuccessfulMatchTime = t`; `comboExpiresAt = t + comboWindow`.
6. Returns `MatchScore(earned, multiplier, combo, speedBonus)` for feedback.

Example: matches at 0 s (+100 ×1), 0.8 s (×2 +50 = +250), 2.3 s (gap 1.5 s: ×3 +25 = +325), 6.0 s (gap 3.7 s: reset,
+100 ×1).

`int onBlockedTap()` — called once per `TapOutcome.blocked` (a covered or side-blocked tile): `score = max(0, score −
blockedTapPenalty)`, and the active combo ends (as `endCombo`), so the next match starts at ×1. `bestCombo` and
`totalPairsMatched` are kept. Returns the points actually taken (1, or 0 when the score was already 0) for feedback.
Each blocked tap counts (tapping the same blocked tile twice costs 2). Taps the controller refuses before the engine
(during the level intro, while a card is open) and `ignored` taps (game over, a tile already in the tray or cleared)
cost nothing.

Other operations: `bool isComboActive(Duration t)` (`currentCombo ≥ 1 && t ≤ comboExpiresAt`); `void endCombo()`
(Revive: combo and last-match time cleared, score/best kept); `void reset()` (Restart: everything zero).
Expiry never changes `score` or `bestCombo`.

**Time source.** `GameController.elapsed` — the game clock built on a `Stopwatch`: monotonic, excludes the level
intro, stops while the app is in the background (`pauseClock`/`resumeClock`) and while the Restart confirm card is
open. No wall clock, formatted strings or frame counts. The controller's stopwatch becomes injectable (a small
`GameClock`/stopwatch factory parameter) so controller tests control time; `ScoreKeeper` itself receives times as
arguments.

**What scores.** Only `TapOutcome.matched` from `GameEngine.tap` — the engine has confirmed the match and removed the
pair. `TapOutcome.blocked` applies the penalty above. `toTray`, `ignored`, `trayFull` change nothing. One tap yields at most one `matched`, so a pair can never
count twice. Animation callbacks (`pairImpact`) only show feedback.

**Stale work.** `GameController` keeps a game serial, incremented by `restart()`. The combo-expiry timer and the
queued feedback carry the serial and are dropped if it changed.

**Combo expiry on screen.** When a combo starts or grows, the controller schedules one timer for the remaining window
to notify listeners when it ends; `pauseClock` cancels it and `resumeClock` re-schedules it for the remaining time.

## 2. Saving and records

**Game in progress** (`SavedGame`, key `progress.current.v2`): a new optional `scoring` object —
`{score, combo, bestCombo, pairs, lastMatchAtMs}` (`lastMatchAtMs` on the game clock, null when no match yet).
`elapsedMs` is already saved, so on resume an active combo continues with exactly the remaining window.
Saves written before this change have no `scoring`: replaying their tap history rebuilds the score at
`basePoints` per match (×1, no speed bonus, best combo 1 if any match) — lower, never broken.
Replays of already-won levels are not saved (highest-level rule, commit a08d198), so their score isn't either.

**Per-level records** (`LevelRecord`, key `progress.completed.v1`): add `bestScore` and `bestCombo` (nullable; records
from before scoring have none). `ProgressRepository.recordWin(levelId, {moves, timeMs, score, bestCombo})` keeps the
highest score and the highest combo independently; fastest time + its date stay as today; best moves as today.
Replays count toward the bests. `GameController` reads the previous `bestScore` before recording to know whether this
win is a **new best score**.

**Play Games piece 2 (not built here):** total-score leaderboard = sum of `bestScore` over all levels (only ever goes
up); combo achievement(s) read `bestCombo`.

## 3. HUD, feedback, win card

**Bottom bar** (`_Hud`): Back · level title · **SCORE** · PAIRS · TIME · Restart. The score counts up to its new value
over ~300 ms after a change, then stops. Moves leave the bar.

**Combo badge** (new widget, between the tray and the board, centred, `IgnorePointer`): a gold glass pill
**"COMBO ×N"** from ×2 up, with a thin ring that shrinks over the remaining window (animates only while a combo is
active, ≤ 3 s at a time, frozen while the clock is paused). Under it, small muted **"Best ×N"** (this game's best
combo); with no active combo only that line shows. Intensity by level, each effect played once when reached:
×2 soft gold; ×3 brighter rim + faint glow; ×4 a 6–8-spark gold burst; ×5+ one shimmer sweep.

**Match popup** (one lightweight overlay, ticks only while popups live, `IgnorePointer`): at the pair's strike in the
tray (`pairImpact`) a small "+250" rises from that tray slot with "×2 · +50 fast" under it — scale-in 120 ms, then
rise and fade 700 ms; stays in the tray-to-board gap, never over tiles. `pairImpact` takes the oldest queued
`MatchScore` (FIFO, cleared on Restart/Revive). Fades via paint colour alpha, never `Opacity` layers (CLAUDE.md).

**Blocked-tap feedback:** a small muted-rose "−1" fades up from the tapped tile for ~500 ms (same overlay,
`IgnorePointer`, tiny so it never hides tiles); nothing when the score was already 0. If a combo was running, the
badge drops away at once.

**Reduce motion:** no popups, no ring animation, no bursts; numbers and badge update in place.

**Level complete card** (below the looping `WinTrophy`): "Level complete!", **Score N** (large, gold) with
**"New best!"** when applicable; Time · Moves; Best combo ×N · Pairs n/n; **"Best: <bestScore> · <fastest time>"**.
Buttons unchanged. No hints/undo/shuffle rows.

**Completed Levels** rows: add the level's **best score** in small gold type under the best time; "—" when the record
has none.

**Rendering rules (CLAUDE.md):** no `BackdropFilter`, no `Opacity`/`ColorFilter` layers, no per-frame blur or blend
passes; static parts of the badge in `StaticLayer`; nothing ticks when no combo, popup or burst is running.

## 4. Tests

`test/game_engine/score_keeper_test.dart` (pure Dart, times as arguments):
first match (+100, ×1, no bonus); consecutive matches inside the window (×2, ×3 with bonuses); boundaries — gap
3.000 s continues (+10), 3.001 s resets; 0.999 s → +50, 1.000 s → +25, 2.000 s → +10; expiry → next match ×1, score
and best kept; max multiplier — 6th/7th fast matches stay ×5 with streak 6/7; best combo across streaks;
`endCombo` (Revive) and `reset` (Restart); blocked tap → −1 and combo ends, best combo kept; blocked tap at score 0
stays 0 (and at score 1 → 0, never negative); repeated blocked taps each cost 1; `toJson`/`fromJson` round trip incl.
an active combo.

`GameController` tests (existing helpers, injected clock): only `matched` adds points; `blocked` costs 1 (never below
0) and ends the combo; toTray/ignored/trayFull and taps refused during the intro change nothing; `pairImpact` and stale timers after Restart don't change the score; pause/resume (background, Restart card)
freezes the window; resume from a save restores scoring; legacy save rebuilds at base points; win records best score
and best combo, a worse replay doesn't lower them, a better one raises them and reports new best.

Widget tests: SCORE in the bar instead of Moves; badge appears at ×2 and goes on expiry; popups don't block taps and
are absent with reduce motion; win card fields and "New best!"; Completed Levels best score / "—"; 360×640 at 1.3×
text has no overflow.

Checks: `dart format`, `flutter analyze` clean, full `flutter test` with no new failures (6 pre-existing failures from
the RenderFlex overflow at `lib/features/levels/level_select_screen.dart:232` are known), captures and an emulator run.

## Files (expected)

- New: `lib/game_engine/scoring/scoring_rules.dart`, `score_keeper.dart`; combo badge and score popup widgets under
  `lib/features/gameplay/widgets/`.
- Modified: `lib/features/gameplay/game_controller.dart` (keeper, serial, clock injection, save/restore, win record),
  `lib/features/gameplay/game_screen.dart` (HUD, badge, popup overlay, win card), `lib/data/progress_repository.dart`
  (`SavedGame.scoring`, `LevelRecord.bestScore/bestCombo`, `recordWin`), `lib/features/levels/level_select_screen.dart`
  (row), CLAUDE.md.

## Out of scope

Leaderboard/achievement submission (Play Games piece 2); any Undo/Hint/Shuffle; Settings changes; changing level
generation or difficulty.
