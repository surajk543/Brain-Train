import 'package:flutter/material.dart';

/// Brand colours.
abstract final class BrainTrainColors {
  static const Color ivory = Color(0xFFF6ECD4);
  static const Color gold = Color(0xFFE9C46A);
  static const Color goldDeep = Color(0xFFB8892B);
  static const Color ink = Color(0xFF12261D);
}

/// Colours for Brain Train's custom surfaces (felt, glass, level backdrops,
/// HUD text). Read with `BrainTrainPalette.of(context)`.
///
/// Brain Train is night-only: [night] is the one palette. [isNight] stays
/// (always true) for code written when a day palette existed.
@immutable
class BrainTrainPalette extends ThemeExtension<BrainTrainPalette> {
  const BrainTrainPalette({
    required this.isNight,
    required this.feltLight,
    required this.felt,
    required this.feltDark,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.panel,
    required this.glassTint,
    required this.glassShade,
    required this.glassBorder,
    required this.backdropBase,
    required this.backdropMix,
    required this.orbStrength,
    required this.scrim,
  });

  static const night = BrainTrainPalette(
    isNight: true,
    feltLight: Color(0xFF1E6B4E),
    felt: Color(0xFF14513B),
    feltDark: Color(0xFF0A2E22),
    text: BrainTrainColors.ivory,
    textMuted: Color(0xA6F6ECD4),
    accent: BrainTrainColors.gold,
    panel: Color(0xCC0B2A20),
    glassTint: 0.10,
    glassShade: 0.16,
    glassBorder: Color(0x38FFFFFF),
    backdropBase: Color(0xFF06120D),
    backdropMix: 0.78,
    orbStrength: 1,
    scrim: Color(0x5904140E),
  );

  final bool isNight;
  final Color feltLight;
  final Color felt;
  final Color feltDark;

  /// Main text and icon colour on felt and glass.
  final Color text;
  final Color textMuted;

  /// Gold accent.
  final Color accent;

  /// Opaque-ish card fill.
  final Color panel;

  /// White frosting strength of glass panels (0-1).
  final double glassTint;

  /// Extra darkening of the board's glass tray, for tile contrast.
  final double glassShade;
  final Color glassBorder;

  /// Tone a level backdrop's first colour is mixed toward, and how much.
  final Color backdropBase;
  final double backdropMix;
  final double orbStrength;

  /// Behind result cards over the board.
  final Color scrim;

  static BrainTrainPalette of(BuildContext context) => Theme.of(context).extension<BrainTrainPalette>() ?? night;

  @override
  BrainTrainPalette copyWith() => this;

  @override
  BrainTrainPalette lerp(BrainTrainPalette? other, double t) => t < 0.5 || other == null ? this : other;
}

/// The app theme. Brain Train is night-only, so [brightness] is ignored and
/// the result is always the dark (night) theme; the parameter is kept for
/// existing callers.
ThemeData buildBrainTrainTheme([Brightness brightness = Brightness.dark]) {
  const palette = BrainTrainPalette.night;
  const lobby = LobbyTheme.night;
  final scheme = ColorScheme.fromSeed(seedColor: palette.felt, brightness: Brightness.dark).copyWith(
    primary: BrainTrainColors.gold,
    onPrimary: BrainTrainColors.ink,
    secondary: palette.text,
    surface: palette.feltDark,
    onSurface: palette.text,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: Brightness.dark);
  return base.copyWith(
    extensions: const [palette, lobby],
    scaffoldBackgroundColor: palette.feltDark,
    textTheme: base.textTheme.apply(bodyColor: palette.text, displayColor: palette.text),
    iconTheme: const IconThemeData(color: BrainTrainColors.ivory),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: BrainTrainColors.ivory,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: BrainTrainColors.gold,
        foregroundColor: BrainTrainColors.ink,
        minimumSize: const Size(220, 56),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.text,
        minimumSize: const Size(220, 50),
        side: BorderSide(color: palette.text.withValues(alpha: 0.45)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    cardTheme: CardThemeData(
      color: palette.panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: palette.accent.withValues(alpha: 0.22)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? lobby.panelAccent : const Color(0xFFB9C7BE),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? const Color(0xFF2E6B4C) : const Color(0x66021A14),
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? lobby.panelAccent : lobby.panelBorder,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: BrainTrainColors.ivory,
      contentTextStyle: TextStyle(color: BrainTrainColors.ink, fontWeight: FontWeight.w600),
    ),
  );
}

/// Screen corner (or bottom centre) a lobby decoration layer is pinned to.
enum LobbyAnchor { topLeft, topRight, bottomLeft, bottomRight, bottomCenter }

/// A soft radial light, drawn by Flutter above the lobby's background art.
@immutable
class LobbyGlow {
  const LobbyGlow({required this.center, required this.radius, required this.color, this.squash = 1});

  /// Centre within the box it belongs to (the screen, or a decor image).
  final Alignment center;

  /// Radius as a fraction of that box's width.
  final double radius;

  /// Colour at the centre; fades to transparent at [radius].
  final Color color;

  /// Vertical scale of the glow (1 = circle).
  final double squash;
}

/// One bundled art layer of the lobby scene (see tool/assets/make_lobby_art.py).
@immutable
class LobbyDecor {
  const LobbyDecor(
    this.asset, {
    required this.anchor,
    required this.width,
    required this.aspect,
    this.dx = 0,
    this.dy = 0,
    this.opacity = 1,
    this.flipX = false,
    this.glow,
  });

  final String asset;
  final LobbyAnchor anchor;

  /// Width as a fraction of the screen width.
  final double width;

  /// Image height / width.
  final double aspect;

  /// Inset from the anchored side, as a fraction of the screen width
  /// (negative pushes the layer past the edge).
  final double dx;

  /// Inset from the anchored top/bottom, as a fraction of the screen height.
  final double dy;
  final double opacity;
  final bool flipX;

  /// Light emitted by this layer (lanterns), relative to its image box.
  final LobbyGlow? glow;
}

/// Everything the lobby (home, Levels, Settings) needs to look right: the
/// night garden's art layers, lighting, fireflies, tagline glass, buttons, panels
/// and text colours. Read with `LobbyTheme.of(context)`; widgets take all
/// colours and assets from here instead of hard-coding them.
@immutable
class LobbyTheme extends ThemeExtension<LobbyTheme> {
  const LobbyTheme({
    required this.baseAsset,
    required this.baseAspect,
    required this.baseFallback,
    required this.decor,
    required this.lights,
    required this.contentScrim,
    required this.edgeVignette,
    required this.subScreenScrim,
    required this.particleCount,
    required this.particleColor,
    required this.particleSize,
    required this.leafCount,
    required this.subScreenLeafCount,
    required this.leafOpacity,
    required this.glassFill,
    required this.glassBlur,
    required this.glassBorder,
    required this.glassHighlight,
    required this.glassShadow,
    required this.taglineGlow,
    required this.taglineLead,
    required this.taglineGradient,
    required this.taglineTextGlow,
    required this.buttonLeafAsset,
    required this.buttonLeafAspect,
    required this.primaryFill,
    required this.primaryEdge,
    required this.primaryText,
    required this.primaryShadow,
    required this.primaryGlow,
    required this.secondaryFill,
    required this.secondaryBorder,
    required this.secondaryText,
    required this.secondaryIcon,
    required this.secondaryShadow,
    required this.primaryGlassFill,
    required this.primaryGlassRim,
    required this.primaryGlassText,
    required this.primaryGlassGlow,
    required this.secondaryGlassFill,
    required this.secondaryGlassRim,
    required this.footerText,
    required this.panelFill,
    required this.panelBorder,
    required this.panelText,
    required this.panelMuted,
    required this.panelAccent,
    required this.textShadow,
  });

  /// Deep emerald forest after dark: lanterns, fireflies, cobblestones.
  static const night = LobbyTheme(
    baseAsset: 'assets/lobby/night_base.webp',
    baseAspect: 2340 / 1080,
    baseFallback: [Color(0xFF082824), Color(0xFF0A4433), Color(0xFF08392F), Color(0xFF062C25)],
    decor: [
      LobbyDecor(
        'assets/lobby/night_path.webp',
        anchor: LobbyAnchor.bottomCenter,
        width: 1.04,
        aspect: 640 / 1080,
        opacity: 0.9,
      ),
      LobbyDecor(
        'assets/lobby/night_lantern.webp',
        anchor: LobbyAnchor.topLeft,
        width: 0.18,
        aspect: 820 / 360,
        dx: -0.05,
        dy: 0.3,
        glow: LobbyGlow(center: Alignment(0, 0.28), radius: 1.6, color: Color(0x5CFFB65C)),
      ),
      LobbyDecor(
        'assets/lobby/night_lantern.webp',
        anchor: LobbyAnchor.topRight,
        width: 0.18,
        aspect: 820 / 360,
        dx: -0.05,
        dy: 0.5,
        flipX: true,
        glow: LobbyGlow(center: Alignment(0, 0.28), radius: 1.6, color: Color(0x5CFFB65C)),
      ),
      LobbyDecor(
        'assets/lobby/night_foliage_tr.webp',
        anchor: LobbyAnchor.topRight,
        width: 0.66,
        aspect: 1000 / 780,
        dx: -0.12,
        dy: -0.035,
      ),
      LobbyDecor(
        'assets/lobby/night_foliage_tl.webp',
        anchor: LobbyAnchor.topLeft,
        width: 0.62,
        aspect: 900 / 760,
        dx: -0.08,
        dy: -0.03,
      ),
      LobbyDecor(
        'assets/lobby/night_foliage_bl.webp',
        anchor: LobbyAnchor.bottomLeft,
        width: 0.5,
        aspect: 1,
        dx: -0.09,
        dy: -0.03,
      ),
      LobbyDecor(
        'assets/lobby/night_foliage_br.webp',
        anchor: LobbyAnchor.bottomRight,
        width: 0.52,
        aspect: 1,
        dx: -0.1,
        dy: -0.035,
      ),
    ],
    lights: [
      LobbyGlow(center: Alignment(0, -1.0), radius: 0.8, color: Color(0x1A9FE0C8), squash: 0.7),
      LobbyGlow(center: Alignment(0, 1.05), radius: 0.7, color: Color(0x26FFB65C), squash: 0.45),
    ],
    contentScrim: Color(0x7A021A14),
    edgeVignette: Color(0x73010E0B),
    subScreenScrim: Color(0x8C03201A),
    particleCount: 36,
    particleColor: Color(0xFFFFDB86),
    particleSize: 2.6,
    leafCount: 14,
    subScreenLeafCount: 9,
    leafOpacity: 0.9,
    glassFill: [Color(0x38E8FFF4), Color(0x1A9FE0C2), Color(0x2A0A4433)],
    glassBlur: 14,
    glassBorder: [Color(0xCCFFF6DC), Color(0x40F4CB72), Color(0x1AFFFFFF), Color(0x66F4CB72)],
    glassHighlight: Color(0x40FFFFFF),
    glassShadow: Color(0x8C000000),
    taglineGlow: Color(0x4DF4CB72),
    taglineLead: Color(0xFFFFF3D8),
    taglineGradient: [Color(0xFFFFF4CC), Color(0xFFF8DA8C), Color(0xFFF4CB72), Color(0xFFC08A2C)],
    taglineTextGlow: Color(0x80F4CB72),
    buttonLeafAsset: 'assets/lobby/button_leaf.webp',
    buttonLeafAspect: 170 / 240,
    primaryFill: [Color(0xFFFAE0A0), Color(0xFFF4CB72), Color(0xFFCF9E42)],
    primaryEdge: Color(0xFFFFEDB8),
    primaryText: Color(0xFF183D2D),
    primaryShadow: Color(0x99000000),
    primaryGlow: Color(0x40F4CB72),
    secondaryFill: [Color(0xD90A4433), Color(0xE608392F)],
    secondaryBorder: Color(0xCCF4CB72),
    secondaryText: Color(0xFFFFF3D8),
    secondaryIcon: Color(0xFFF4CB72),
    secondaryShadow: Color(0x80000000),
    primaryGlassFill: [Color(0xD6FFE9A8), Color(0xBAF8D56E), Color(0xC7EBB440)],
    primaryGlassRim: [Color(0xFFFFF4CC), Color(0xCCF4CB72), Color(0x66C08A2C), Color(0xE6F8DA8C)],
    primaryGlassText: Color(0xFF183D2D),
    primaryGlassGlow: Color(0x80F4CB72),
    secondaryGlassFill: [Color(0x30E8FFF4), Color(0x149FE0C2), Color(0x330A4433)],
    secondaryGlassRim: [Color(0xCCFFF6DC), Color(0x99F4CB72), Color(0x33FFFFFF), Color(0x99F4CB72)],
    footerText: Color(0xB3FFF3D8),
    panelFill: Color(0xD908392F),
    panelBorder: Color(0x80F4CB72),
    panelText: Color(0xFFFFF3D8),
    panelMuted: Color(0xA6FFF3D8),
    panelAccent: Color(0xFFF4CB72),
    textShadow: Color(0xB3000000),
  );

  /// Opaque garden backdrop (cover fit; height / width), and the gradient
  /// shown under it while it decodes so the lobby is never blank.
  final String baseAsset;
  final double baseAspect;
  final List<Color> baseFallback;

  /// Art layers above the base, back to front.
  final List<LobbyDecor> decor;

  /// Screen-level lighting above the art.
  final List<LobbyGlow> lights;

  /// Calm radial shade behind the tagline and buttons, for contrast.
  final Color contentScrim;
  final Color edgeVignette;

  /// Extra shade over the scene on the Levels and Settings screens.
  final Color subScreenScrim;

  /// Fireflies.
  final int particleCount;
  final Color particleColor;
  final double particleSize;

  /// Drifting leaves (see FlowingLeaves): how many on home and on the
  /// Levels/Settings screens, and their overall opacity.
  final int leafCount;
  final int subScreenLeafCount;
  final double leafOpacity;

  /// Frosted-glass tagline panel: tint (top to bottom), backdrop blur
  /// sigma, gradient rim (top-left to bottom-right), inner top highlight
  /// and drop shadow.
  final List<Color> glassFill;
  final double glassBlur;
  final List<Color> glassBorder;
  final Color glassHighlight;
  final Color glassShadow;

  /// Warm light behind the panel.
  final Color taglineGlow;

  /// "Train your" (ivory) and "brain" (gold, top to bottom, with a glow).
  final Color taglineLead;
  final List<Color> taglineGradient;
  final Color taglineTextGlow;

  /// Leaves tucked behind button ends.
  final String buttonLeafAsset;
  final double buttonLeafAspect;

  /// Primary (Play/Continue) button.
  final List<Color> primaryFill;
  final Color primaryEdge;
  final Color primaryText;
  final Color primaryShadow;
  final Color primaryGlow;

  /// Secondary (Levels, Settings) buttons.
  final List<Color> secondaryFill;
  final Color secondaryBorder;
  final Color secondaryText;
  final Color secondaryIcon;
  final Color secondaryShadow;

  /// Glass lobby buttons. Play: gold-tinted frost (fill top-left to
  /// bottom-right), bright gold rim and dark-green label.
  final List<Color> primaryGlassFill;
  final List<Color> primaryGlassRim;
  final Color primaryGlassText;

  /// Warm halo around the Play glass pill.
  final Color primaryGlassGlow;

  /// Levels, Settings and the round buttons: clear frost with a fine gold rim.
  final List<Color> secondaryGlassFill;
  final List<Color> secondaryGlassRim;

  final Color footerText;

  /// Cards on the Levels and Settings screens.
  final Color panelFill;
  final Color panelBorder;
  final Color panelText;
  final Color panelMuted;
  final Color panelAccent;

  /// Shadow under text drawn straight on the scene.
  final Color textShadow;

  static LobbyTheme of(BuildContext context) => Theme.of(context).extension<LobbyTheme>() ?? night;

  @override
  LobbyTheme copyWith() => this;

  @override
  LobbyTheme lerp(LobbyTheme? other, double t) => t < 0.5 || other == null ? this : other;
}
