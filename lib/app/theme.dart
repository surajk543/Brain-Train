import 'package:flutter/material.dart';

import '../data/appearance.dart';
import 'brand.dart';
import 'typography.dart';

/// Brand colours.
abstract final class BrainTrainColors {
  static const Color ivory = Color(0xFFF6ECD4);
  static const Color gold = Color(0xFFE9C46A);
  static const Color goldDeep = Color(0xFFB8892B);
  static const Color ink = Color(0xFF12261D);

  /// Reference board (redesign 1.1.0): Day.
  static const Color gardenGreen = Color(0xFF1D6B43);
  static const Color deepFoliage = Color(0xFF104B34);
  static const Color dayGold = Color(0xFFF2C96B);
  static const Color warmIvory = Color(0xFFFFF6DF);

  /// Dark green text on gold and ivory (both looks).
  static const Color darkGreenText = Color(0xFF183D2D);

  /// Reference board: Night.
  static const Color deepEmerald = Color(0xFF062C25);
  static const Color forest = Color(0xFF0A4433);
  static const Color nightPanel = Color(0xFF08392F);
  static const Color nightGold = Color(0xFFF4CB72);
  static const Color paleIvory = Color(0xFFFFF3D8);
}

/// The gameplay felt's corner foliage (`assets/decor/`, made by
/// tool/assets/make_foliage.py).
@immutable
class FeltFoliage {
  const FeltFoliage({required this.right, required this.topLeft, required this.bottomLeft, required this.bottomRight});

  static const night = FeltFoliage(
    right: 'assets/decor/foliage_right.webp',
    topLeft: 'assets/decor/foliage_top_left.webp',
    bottomLeft: 'assets/decor/foliage_bottom_left.webp',
    bottomRight: 'assets/decor/foliage_bottom_right.webp',
  );

  // TODO(redesign 1.1, gameplay phase): Day foliage art; Day uses the night
  // foliage until it exists.
  static const day = night;

  final String right;
  final String topLeft;
  final String bottomLeft;
  final String bottomRight;
}

/// Colours for Brain Train's custom surfaces (felt, panels, HUD, buttons,
/// glass, level backdrops, text). Read with `BrainTrainPalette.of(context)`;
/// screens take colours from here (and the lobby scene from [LobbyTheme])
/// instead of hard-coding them.
///
/// Two looks (owner, 2026-10-17, redesign 1.1.0): [day] (garden green) and
/// [night] (deep emerald), chosen by the Appearance setting (Day, Night or
/// the phone's setting). Panels are dark translucent green with a fine gold
/// rim in both, so text on panels is ivory in both; only text on gold or
/// ivory surfaces is dark green ([textOnGold]). Tiles look the same in both.
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
    required this.background,
    required this.feltCenter,
    required this.feltMid,
    required this.feltEdge,
    required this.feltNap,
    required this.feltGlow,
    required this.feltGlowStrength,
    required this.feltVignette,
    required this.feltFoliage,
    required this.panelFill,
    required this.panelRim,
    required this.panelSheen,
    required this.panelHighlight,
    required this.panelShadows,
    required this.hudFill,
    required this.hudSeparator,
    required this.hudLabel,
    required this.hudValue,
    required this.primaryButtonFill,
    required this.primaryButtonEdge,
    required this.primaryButtonText,
    required this.primaryButtonShadow,
    required this.secondaryButtonFill,
    required this.secondaryButtonBorder,
    required this.secondaryButtonText,
    required this.quietButtonText,
    required this.textOnGold,
    required this.accentLight,
    required this.accentDeep,
    required this.textShadow,
    required this.shadow,
    required this.overlayScrim,
  });

  /// Deep emerald (the look before 1.1.0, unchanged).
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
    background: [BrainTrainColors.forest, BrainTrainColors.nightPanel, BrainTrainColors.deepEmerald],
    feltCenter: Color(0xFF1B6B45),
    feltMid: Color(0xFF0E4A2F),
    feltEdge: Color(0xFF062618),
    feltNap: 0.018,
    feltGlow: Color(0xFFFFD98A),
    feltGlowStrength: 0.4,
    feltVignette: 0.34,
    feltFoliage: FeltFoliage.night,
    panelFill: [Color(0xD11A5638), Color(0xE00A3322)],
    panelRim: [BrandGold.light, BrandGold.base, BrandGold.deep, BrandGold.base, BrandGold.light],
    panelSheen: Color(0x12FFFFFF),
    panelHighlight: Color(0x42FFFFFF),
    panelShadows: [
      BoxShadow(color: Color(0x59000000), blurRadius: 24, offset: Offset(0, 10)),
      BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2)),
    ],
    hudFill: [Color(0xD11A5638), Color(0xE00A3322)],
    hudSeparator: BrandGold.base,
    hudLabel: Color(0xC7F6ECD4),
    hudValue: BrainTrainColors.ivory,
    primaryButtonFill: [BrandGold.light, BrandGold.warm, BrandGold.base],
    primaryButtonEdge: Color(0xFFFFF1C4),
    primaryButtonText: BrainTrainColors.ink,
    primaryButtonShadow: Color(0x55000000),
    secondaryButtonFill: Color(0x0AFFFFFF),
    secondaryButtonBorder: BrandGold.base,
    secondaryButtonText: BrainTrainColors.ivory,
    quietButtonText: BrandGold.light,
    textOnGold: BrainTrainColors.darkGreenText,
    accentLight: BrandGold.light,
    accentDeep: BrandGold.deep,
    textShadow: Color(0xB3000000),
    shadow: Color(0x59000000),
    overlayScrim: Color(0x8C020D08),
  );

  /// Garden green by day: a brighter felt and background, warm sunlight;
  /// the same dark-green gold-rimmed panels, gold buttons and ivory text.
  static const day = BrainTrainPalette(
    isNight: false,
    feltLight: Color(0xFF2B7F52),
    felt: BrainTrainColors.gardenGreen,
    feltDark: BrainTrainColors.deepFoliage,
    text: BrainTrainColors.warmIvory,
    textMuted: Color(0xB8FFF6DF),
    accent: BrainTrainColors.dayGold,
    panel: Color(0xD90C3A28),
    glassTint: 0.10,
    glassShade: 0.18,
    glassBorder: Color(0x38FFFFFF),
    backdropBase: Color(0xFF0C3A28),
    backdropMix: 0.7,
    orbStrength: 1,
    scrim: Color(0x5904140E),
    background: [Color(0xFF2A7F50), BrainTrainColors.gardenGreen, BrainTrainColors.deepFoliage],
    feltCenter: Color(0xFF287D4F),
    feltMid: BrainTrainColors.gardenGreen,
    feltEdge: BrainTrainColors.deepFoliage,
    feltNap: 0.022,
    feltGlow: Color(0xFFFFE6A6),
    feltGlowStrength: 0.46,
    feltVignette: 0.24,
    feltFoliage: FeltFoliage.day,
    panelFill: [Color(0xD91A5638), Color(0xE60A3322)],
    panelRim: [BrandGold.light, BrandGold.base, BrandGold.deep, BrandGold.base, BrandGold.light],
    panelSheen: Color(0x12FFFFFF),
    panelHighlight: Color(0x42FFFFFF),
    panelShadows: [
      BoxShadow(color: Color(0x4D000000), blurRadius: 24, offset: Offset(0, 10)),
      BoxShadow(color: Color(0x2E000000), blurRadius: 4, offset: Offset(0, 2)),
    ],
    hudFill: [Color(0xD91A5638), Color(0xE60A3322)],
    hudSeparator: BrandGold.base,
    hudLabel: Color(0xCCFFF6DF),
    hudValue: BrainTrainColors.warmIvory,
    primaryButtonFill: [BrandGold.light, BrainTrainColors.dayGold, BrandGold.base],
    primaryButtonEdge: Color(0xFFFFF1C4),
    primaryButtonText: BrainTrainColors.ink,
    primaryButtonShadow: Color(0x4D000000),
    secondaryButtonFill: Color(0x0AFFFFFF),
    secondaryButtonBorder: BrandGold.base,
    secondaryButtonText: BrainTrainColors.warmIvory,
    quietButtonText: BrandGold.light,
    textOnGold: BrainTrainColors.darkGreenText,
    accentLight: BrandGold.light,
    accentDeep: BrandGold.deep,
    textShadow: Color(0xA6000000),
    shadow: Color(0x4D000000),
    overlayScrim: Color(0x80041A10),
  );

  /// The look for a brightness: light is Day, dark is Night.
  static BrainTrainPalette forBrightness(Brightness brightness) => brightness == Brightness.light ? day : night;

  /// True for [night], false for [day].
  final bool isNight;
  bool get isDay => !isNight;

  final Color feltLight;
  final Color felt;

  /// Scaffold background under every screen.
  final Color feltDark;

  /// Main text and icon colour on felt, panels and glass (ivory in both looks).
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

  /// Plain screen background, top to bottom (screens without the lobby scene
  /// or the felt).
  final List<Color> background;

  /// Gameplay felt: radial gradient centre, middle and edge (the edge is
  /// also the game screen's Scaffold colour), the strength (alpha) of the
  /// fine diagonal nap, the warm light from the top-right (mixed with the
  /// level's colour) and its strength, and the vignette's darkness (alpha).
  final Color feltCenter;
  final Color feltMid;
  final Color feltEdge;
  final double feltNap;
  final Color feltGlow;
  final double feltGlowStrength;
  final double feltVignette;

  /// Foliage art at the felt's edges.
  final FeltFoliage feltFoliage;

  /// Dark translucent green panels (HUD, tray, result cards): fill top to
  /// bottom, gold rim (top-left to bottom-right), the soft sheen inside the
  /// top half, the fine highlight along the top edge, and the drop shadows.
  final List<Color> panelFill;
  final List<Color> panelRim;
  final Color panelSheen;
  final Color panelHighlight;
  final List<BoxShadow> panelShadows;

  /// The HUD bar: fill top to bottom, the gold of its separators (faded at
  /// both ends), small caps labels and values.
  final List<Color> hudFill;
  final Color hudSeparator;
  final Color hudLabel;
  final Color hudValue;

  /// Gold button (Next level, Revive, Restart): fill top to bottom, edge,
  /// label and drop shadow.
  final List<Color> primaryButtonFill;
  final Color primaryButtonEdge;
  final Color primaryButtonText;
  final Color primaryButtonShadow;

  /// Outlined button on a panel: faint fill, gold border (full strength;
  /// widgets fade it), label. [quietButtonText] is the borderless button's
  /// label.
  final Color secondaryButtonFill;
  final Color secondaryButtonBorder;
  final Color secondaryButtonText;
  final Color quietButtonText;

  /// Dark green text on gold or ivory surfaces (never gold on ivory).
  final Color textOnGold;

  /// Light and deep golds (rims, highlights, sprigs).
  final Color accentLight;
  final Color accentDeep;

  /// Shadow under text drawn straight on the felt or scene.
  final Color textShadow;

  /// Generic drop shadow colour.
  final Color shadow;

  /// Dims the board around result and confirm cards.
  final Color overlayScrim;

  static BrainTrainPalette of(BuildContext context) => Theme.of(context).extension<BrainTrainPalette>() ?? night;

  @override
  BrainTrainPalette copyWith() => this;

  @override
  BrainTrainPalette lerp(BrainTrainPalette? other, double t) => t < 0.5 || other == null ? this : other;
}

/// How [MaterialApp.themeMode] follows the Appearance setting.
extension AppAppearanceThemeMode on AppAppearance {
  ThemeMode get themeMode => switch (this) {
    AppAppearance.system => ThemeMode.system,
    AppAppearance.day => ThemeMode.light,
    AppAppearance.night => ThemeMode.dark,
  };
}

/// The app theme for [brightness]: [Brightness.light] is Day, dark is Night
/// (the default, for existing callers). Both carry [BrainTrainPalette],
/// [LobbyTheme] and [BrainTrainTypography] for their look. The app passes
/// both to `MaterialApp` (`theme` = Day, `darkTheme` = Night) with the
/// Appearance setting's `themeMode`.
///
/// Body text is Manrope and display styles Playfair Display (bundled). Day
/// keeps dark-green surfaces (panels, dialogs) with ivory text, like the
/// reference board, so nothing renders gold or ivory on a light surface.
ThemeData buildBrainTrainTheme([Brightness brightness = Brightness.dark]) =>
    brightness == Brightness.light ? _dayTheme : _nightTheme;

final ThemeData _nightTheme = _buildTheme(Brightness.dark);
final ThemeData _dayTheme = _buildTheme(Brightness.light);

ThemeData _buildTheme(Brightness brightness) {
  final palette = BrainTrainPalette.forBrightness(brightness);
  final lobby = LobbyTheme.forBrightness(brightness);
  final type = brightness == Brightness.light ? BrainTrainTypography.day : BrainTrainTypography.night;
  var scheme = ColorScheme.fromSeed(seedColor: palette.felt, brightness: brightness).copyWith(
    primary: palette.accent,
    onPrimary: BrainTrainColors.ink,
    secondary: palette.text,
    surface: palette.feltDark,
    onSurface: palette.text,
  );
  if (brightness == Brightness.light) {
    // Day: the seed's light surfaces would put ivory and gold on white;
    // dialogs, menus and sheets stay dark green as in the reference.
    scheme = scheme.copyWith(
      onSurfaceVariant: palette.textMuted,
      surfaceContainerLowest: const Color(0xFF0B3826),
      surfaceContainerLow: const Color(0xFF0E412C),
      surfaceContainer: const Color(0xFF104B34),
      surfaceContainerHigh: const Color(0xFF14553B),
      surfaceContainerHighest: const Color(0xFF185F42),
      surfaceTint: palette.accent,
      outline: palette.accent.withValues(alpha: 0.6),
      outlineVariant: palette.accent.withValues(alpha: 0.3),
      inverseSurface: palette.text,
      onInverseSurface: BrainTrainColors.ink,
    );
  }
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    brightness: brightness,
    fontFamily: BrainTrainFonts.ui,
    fontFamilyFallback: BrainTrainFonts.uiFallback,
  );
  TextStyle? display(TextStyle? style, FontWeight weight) => style?.copyWith(
    fontFamily: BrainTrainFonts.display,
    fontFamilyFallback: BrainTrainFonts.displayFallback,
    fontWeight: weight,
  );
  final text = base.textTheme.apply(bodyColor: palette.text, displayColor: palette.text);
  return base.copyWith(
    extensions: [palette, lobby, type],
    scaffoldBackgroundColor: palette.feltDark,
    textTheme: text.copyWith(
      displayLarge: display(text.displayLarge, FontWeight.w700),
      displayMedium: display(text.displayMedium, FontWeight.w700),
      displaySmall: display(text.displaySmall, FontWeight.w700),
      headlineLarge: display(text.headlineLarge, FontWeight.w700),
      headlineMedium: display(text.headlineMedium, FontWeight.w700),
      headlineSmall: display(text.headlineSmall, FontWeight.w700),
      titleLarge: display(text.titleLarge, FontWeight.w600),
    ),
    iconTheme: IconThemeData(color: palette.text),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: palette.text,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: BrainTrainColors.ink,
        minimumSize: const Size(220, 56),
        textStyle: BrainTrainType.button(size: 18).copyWith(letterSpacing: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.text,
        minimumSize: const Size(220, 50),
        side: BorderSide(color: palette.text.withValues(alpha: 0.45)),
        textStyle: BrainTrainType.button(size: 16),
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
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: palette.text,
      contentTextStyle: BrainTrainType.body(size: 14, color: BrainTrainColors.ink, weight: FontWeight.w600),
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

/// One bundled art layer of the lobby scene (Night: tool/assets/make_lobby_art.py;
/// Day and the hero ledges: tool/lobby_art/make_day_lobby_art.py).
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
/// garden's art layers, lighting, ambient particles, the hero ledge and
/// title, buttons, panels and text colours, for Day ([day]) and Night
/// ([night]). Read with `LobbyTheme.of(context)`; widgets take all colours
/// and assets from here instead of hard-coding them.
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
    required this.glassBlur,
    required this.glassHighlight,
    required this.glassShadow,
    required this.heroLedgeAsset,
    required this.heroLedgeAspect,
    required this.titleGradient,
    required this.titleGlow,
    required this.titleShadow,
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

  // The night garden's art layers (tool/assets/make_lobby_art.py).
  static const LobbyGlow _lanternLight = LobbyGlow(center: Alignment(0, 0.28), radius: 1.6, color: Color(0x5CFFB65C));
  static const List<LobbyDecor> _nightFoliage = [
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
  ];

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
        dy: -0.06,
        opacity: 0.9,
      ),
      // Two lanterns down the right side, beside the hero tiles and the
      // status line (reference).
      LobbyDecor(
        'assets/lobby/night_lantern.webp',
        anchor: LobbyAnchor.topRight,
        width: 0.2,
        aspect: 820 / 360,
        dx: -0.045,
        dy: 0.04,
        flipX: true,
        glow: _lanternLight,
      ),
      LobbyDecor(
        'assets/lobby/night_lantern.webp',
        anchor: LobbyAnchor.bottomRight,
        width: 0.15,
        aspect: 820 / 360,
        dx: -0.03,
        dy: 0.1,
        glow: _lanternLight,
      ),
      ..._nightFoliage,
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
    glassBlur: 14,
    glassHighlight: Color(0x40FFFFFF),
    glassShadow: Color(0x8C000000),
    heroLedgeAsset: 'assets/lobby/night_ledge.webp',
    heroLedgeAspect: 360 / 1080,
    titleGradient: [Color(0xFFFFF4CC), Color(0xFFF8DA8C), Color(0xFFF4CB72), Color(0xFFC08A2C)],
    titleGlow: Color(0x4DF4CB72),
    titleShadow: Color(0xCC000000),
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
    primaryGlassFill: [Color(0xFFFFE8A8), Color(0xFFF6CC6C), Color(0xFFD9A042)],
    primaryGlassRim: [Color(0xFFFFF4CC), Color(0xCCF4CB72), Color(0x66C08A2C), Color(0xE6F8DA8C)],
    primaryGlassText: Color(0xFF183D2D),
    primaryGlassGlow: Color(0x80F4CB72),
    secondaryGlassFill: [Color(0xC7124A38), Color(0xBF0A3F30), Color(0xD1083528)],
    secondaryGlassRim: [Color(0xE6FFF0C4), Color(0xCCF4CB72), Color(0x80C08A2C), Color(0xCCF4CB72)],
    footerText: Color(0xB3FFF3D8),
    panelFill: Color(0xD908392F),
    panelBorder: Color(0x80F4CB72),
    panelText: Color(0xFFFFF3D8),
    panelMuted: Color(0xA6FFF3D8),
    panelAccent: Color(0xFFF4CB72),
    textShadow: Color(0xB3000000),
  );

  /// The garden by day (tool/lobby_art/make_day_lobby_art.py): sun through
  /// the leaves from the top right, cream flowers, a mossy stone path, no
  /// lanterns; a few drifting pollen motes instead of fireflies. The same
  /// dark-green glass with fine gold rims, a little denser so ivory and gold
  /// keep their contrast on the brighter scene.
  static const day = LobbyTheme(
    baseAsset: 'assets/lobby/day/day_base.webp',
    baseAspect: 2340 / 1080,
    baseFallback: [Color(0xFF9CC27A), Color(0xFF3E8A55), BrainTrainColors.gardenGreen, BrainTrainColors.deepFoliage],
    decor: [
      LobbyDecor(
        'assets/lobby/day/day_path.webp',
        anchor: LobbyAnchor.bottomCenter,
        width: 1.04,
        aspect: 640 / 1080,
        dy: -0.1,
      ),
      LobbyDecor(
        'assets/lobby/day/day_foliage_ml.webp',
        anchor: LobbyAnchor.topLeft,
        width: 0.42,
        aspect: 900 / 520,
        dx: -0.12,
        dy: 0.34,
      ),
      LobbyDecor(
        'assets/lobby/day/day_foliage_mr.webp',
        anchor: LobbyAnchor.topRight,
        width: 0.42,
        aspect: 900 / 520,
        dx: -0.12,
        dy: 0.44,
      ),
      LobbyDecor(
        'assets/lobby/day/day_foliage_tr.webp',
        anchor: LobbyAnchor.topRight,
        width: 0.66,
        aspect: 1000 / 780,
        dx: -0.12,
        dy: -0.035,
      ),
      LobbyDecor(
        'assets/lobby/day/day_foliage_tl.webp',
        anchor: LobbyAnchor.topLeft,
        width: 0.62,
        aspect: 900 / 760,
        dx: -0.08,
        dy: -0.03,
      ),
      LobbyDecor(
        'assets/lobby/day/day_foliage_bl.webp',
        anchor: LobbyAnchor.bottomLeft,
        width: 0.62,
        aspect: 1,
        dx: -0.08,
        dy: -0.04,
      ),
      LobbyDecor(
        'assets/lobby/day/day_foliage_br.webp',
        anchor: LobbyAnchor.bottomRight,
        width: 0.64,
        aspect: 1,
        dx: -0.09,
        dy: -0.045,
      ),
    ],
    lights: [
      LobbyGlow(center: Alignment(0.6, -1.05), radius: 1.05, color: Color(0x66FFE8A6), squash: 0.9),
      LobbyGlow(center: Alignment(0, 1.05), radius: 0.7, color: Color(0x24FFE7A6), squash: 0.45),
    ],
    contentScrim: Color(0x47052A1A),
    edgeVignette: Color(0x59021A12),
    subScreenScrim: Color(0x9E05281C),
    particleCount: 14,
    particleColor: Color(0xFFFFF6D2),
    particleSize: 1.9,
    leafCount: 12,
    subScreenLeafCount: 8,
    leafOpacity: 0.95,
    glassBlur: 14,
    glassHighlight: Color(0x38FFFFFF),
    glassShadow: Color(0x80021A0E),
    heroLedgeAsset: 'assets/lobby/day/day_ledge.webp',
    heroLedgeAspect: 360 / 1080,
    titleGradient: [Color(0xFFFFF4CC), Color(0xFFF8DA8C), Color(0xFFF2C96B), Color(0xFFB98328)],
    titleGlow: Color(0x40FFE9A8),
    titleShadow: Color(0xD9021A0E),
    buttonLeafAsset: 'assets/lobby/button_leaf.webp',
    buttonLeafAspect: 170 / 240,
    primaryFill: [Color(0xFFFAE0A0), BrainTrainColors.dayGold, Color(0xFFCF9E42)],
    primaryEdge: Color(0xFFFFEDB8),
    primaryText: BrainTrainColors.darkGreenText,
    primaryShadow: Color(0x80000000),
    primaryGlow: Color(0x40F2C96B),
    secondaryFill: [Color(0xE00E4A34), Color(0xEB0A3F2D)],
    secondaryBorder: Color(0xCCF2C96B),
    secondaryText: BrainTrainColors.warmIvory,
    secondaryIcon: BrainTrainColors.dayGold,
    secondaryShadow: Color(0x73000000),
    primaryGlassFill: [Color(0xFFFFE8A8), Color(0xFFF4C966), Color(0xFFD6A042)],
    primaryGlassRim: [Color(0xFFFFF4CC), Color(0xCCF2C96B), Color(0x66C08A2C), Color(0xE6F8DA8C)],
    primaryGlassText: BrainTrainColors.darkGreenText,
    primaryGlassGlow: Color(0x73F2C96B),
    secondaryGlassFill: [Color(0xD1124A36), Color(0xC70C4230), Color(0xD90A3829)],
    secondaryGlassRim: [Color(0xE6FFF0C4), Color(0xD9F2C96B), Color(0x80C08A2C), Color(0xD9F2C96B)],
    footerText: Color(0xE6FFF6DF),
    panelFill: Color(0xE00A3F2D),
    panelBorder: Color(0x99F2C96B),
    panelText: BrainTrainColors.warmIvory,
    panelMuted: Color(0xB8FFF6DF),
    panelAccent: BrainTrainColors.dayGold,
    textShadow: Color(0xB3000000),
  );

  /// The lobby for a brightness: light is Day, dark is Night.
  static LobbyTheme forBrightness(Brightness brightness) => brightness == Brightness.light ? day : night;

  /// Opaque garden backdrop (cover fit; height / width), and the gradient
  /// shown under it while it decodes so the lobby is never blank.
  final String baseAsset;
  final double baseAspect;
  final List<Color> baseFallback;

  /// Art layers above the base, back to front.
  final List<LobbyDecor> decor;

  /// Screen-level lighting above the art.
  final List<LobbyGlow> lights;

  /// Calm radial shade behind the title and buttons, for contrast.
  final Color contentScrim;
  final Color edgeVignette;

  /// Extra shade over the scene on the Levels and Settings screens.
  final Color subScreenScrim;

  /// Ambient particles on home: fireflies at night, pollen by day.
  final int particleCount;
  final Color particleColor;
  final double particleSize;

  /// Drifting leaves (see FlowingLeaves): how many on home and on the
  /// Levels/Settings screens, and their overall opacity.
  final int leafCount;
  final int subScreenLeafCount;
  final double leafOpacity;

  /// Frosted glass (buttons, panels): backdrop blur sigma, the inner top
  /// highlight and the drop shadow.
  final double glassBlur;
  final Color glassHighlight;
  final Color glassShadow;

  /// The mossy ledge the hero tiles stand on (height / width); missing art
  /// just leaves it out.
  final String heroLedgeAsset;
  final double heroLedgeAspect;

  /// The "Brain Train" title: gold top to bottom, the warm halo behind it
  /// and its drop shadow.
  final List<Color> titleGradient;
  final Color titleGlow;
  final Color titleShadow;

  /// Leaves tucked behind the Play button's ends.
  final String buttonLeafAsset;
  final double buttonLeafAspect;

  /// Gold medallions and buttons on panels (Levels).
  final List<Color> primaryFill;
  final Color primaryEdge;
  final Color primaryText;
  final Color primaryShadow;
  final Color primaryGlow;

  /// Dark-green outlined surfaces on panels.
  final List<Color> secondaryFill;
  final Color secondaryBorder;
  final Color secondaryText;
  final Color secondaryIcon;
  final Color secondaryShadow;

  /// Glass lobby buttons. Play: gold glass (fill top-left to bottom-right),
  /// bright gold rim and dark-green label.
  final List<Color> primaryGlassFill;
  final List<Color> primaryGlassRim;
  final Color primaryGlassText;

  /// Warm halo around the Play glass pill.
  final Color primaryGlassGlow;

  /// Levels, Settings and the round buttons: dark-green glass with a fine
  /// gold rim.
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
