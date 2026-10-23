# Sound sources

Every sound the app bundles, where it came from and its licence. The effects were rebuilt on 2026-10-23
(premium pass): picked from Kenney's CC0 packs, trimmed of leading silence, mixed to mono 44.1 kHz 16-bit WAV
and peak-normalized with ffmpeg. Two effects carry a quiet layer of filtered noise generated with ffmpeg
(`anoisesrc`; no source file, no licence needed). Kenney's packs were downloaded on 2026-10-23 and each
`License.txt` in them reads "Creative Commons Zero, CC0"; credit is not required ("Kenney or www.kenney.nl"
would be nice).

| File | What plays it | Source file(s) | Pack (URL) | Creator | Licence | Attribution |
| --- | --- | --- | --- | --- | --- | --- |
| `tap.wav` | Every playable tap (`Sfx.tap`) | `back_002.ogg` | Interface Sounds 1.0 (https://kenney.nl/assets/interface-sounds) | Kenney (kenney.nl) | CC0 1.0 | Not required |
| `tray.wav` | A tile landing in the tray without a match (`Sfx.tray`) | `drop_002.ogg` + `glass_002.ogg` at -12 dB, 30 ms later | Interface Sounds 1.0 (https://kenney.nl/assets/interface-sounds) | Kenney | CC0 1.0 | Not required |
| `match.wav` | A matched pair striking at x1 (`Sfx.match`) | `confirmation_001.ogg` + generated soft whoosh (pink noise, 0.28 s, 300-2600 Hz) | Interface Sounds 1.0 (https://kenney.nl/assets/interface-sounds) | Kenney; whoosh generated | CC0 1.0 | Not required |
| `combo.wav` | A match continuing a combo, x2 and up (`Sfx.combo`) | `confirmation_003.ogg` + the same generated whoosh | Interface Sounds 1.0 (https://kenney.nl/assets/interface-sounds) | Kenney; whoosh generated | CC0 1.0 | Not required |
| `invalid.wav` | A blocked tile tapped (`Sfx.invalid`) | `bong_001.ogg` | Interface Sounds 1.0 (https://kenney.nl/assets/interface-sounds) | Kenney | CC0 1.0 | Not required |
| `hint.wav` | Hint (`Sfx.hint`) | `glass_004.ogg` | Interface Sounds 1.0 (https://kenney.nl/assets/interface-sounds) | Kenney | CC0 1.0 | Not required |
| `undo.wav` | Undo (`Sfx.undo`) | `minimize_005.ogg` | Interface Sounds 1.0 (https://kenney.nl/assets/interface-sounds) | Kenney | CC0 1.0 | Not required |
| `shuffle.wav` | Shuffle (`Sfx.shuffle`) | `maximize_005.ogg` + generated leaf rustle (pink noise, 0.5 s, 1.8-7 kHz, 22 Hz flutter) | Interface Sounds 1.0 (https://kenney.nl/assets/interface-sounds) | Kenney; rustle generated | CC0 1.0 | Not required |
| `win.wav` | Level complete, after the last strike (`Sfx.win`) | `jingles_STEEL10.ogg` (rising steel-drum jingle) | Music Jingles (https://kenney.nl/assets/music-jingles) | Kenney Vleugels (kenney.nl) | CC0 1.0 | Not required |
| `lose.wav` | Tray full (`Sfx.lose`) | `jingles_PIZZI07.ogg` (falling pizzicato phrase) | Music Jingles (https://kenney.nl/assets/music-jingles) | Kenney Vleugels | CC0 1.0 | Not required |
| `select.wav` | A soft tick: intro layers and revived tiles landing (`Sfx.select`) | `tick_004.ogg` | Interface Sounds 1.0 (https://kenney.nl/assets/interface-sounds) | Kenney | CC0 1.0 | Not required |

Levels (peak, dBFS): tap -4, tray -7, match -3, combo -3, invalid -6, hint -8, undo -10, shuffle -9, win -3,
lose -6, select -12.

The UI Audio pack (https://kenney.nl/assets/ui-audio, CC0) was downloaded and checked too; none of its sounds
is used. No Freesound sounds are used.

## Music

| File | What plays it | Source | Licence |
| --- | --- | --- | --- |
| `assets/music/water_flowing.mp3` | Background music, looped at volume 0.4 (`BackgroundMusic`) | Supplied by the owner with the first build (2026-10-16); its original source and licence are not recorded in this repository | Unrecorded: confirm with the owner |

## Replaced sounds

The effects before 2026-10-23 (`tap.wav` cut from the owner's Tap.mp3, `strike.wav` from the owner's impact.mp3,
and `select.wav`, `invalid.wav`, `win.wav`, `lose.wav`) were replaced on the owner's request; they remain in git
history.
