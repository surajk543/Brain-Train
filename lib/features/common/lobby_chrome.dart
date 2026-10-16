import 'package:flutter/material.dart';

import '../../app/brand.dart';
import '../../app/theme.dart';
import 'static_layer.dart';

/// Serif display style in the lobby's text colour, with a soft shadow so it
/// reads on the garden scene.
TextStyle lobbyHeading(BuildContext context, double size, {Color? color, FontWeight weight = FontWeight.w700}) {
  final lobby = LobbyTheme.of(context);
  return displayText(size, color: color ?? lobby.panelText, weight: weight).copyWith(
    shadows: [Shadow(color: lobby.textShadow, blurRadius: 6, offset: const Offset(0, 1.5))],
  );
}

/// Transparent app bar for the Levels and Settings screens: gold serif
/// title, gold back button.
class LobbyAppBar extends StatelessWidget implements PreferredSizeWidget {
  const LobbyAppBar({super.key, required this.title});

  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 4);

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    // The shadowed title and back arrow are static: rendered once each, not
    // on every frame of the leaves behind them. (Not the whole bar: it
    // carries the status bar style, which must stay in the layer tree.)
    return AppBar(
      toolbarHeight: kToolbarHeight + 4,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(
        color: lobby.panelAccent,
        shadows: [Shadow(color: lobby.textShadow, blurRadius: 6)],
      ),
      leading: canPop ? const StaticLayer(overflow: EdgeInsets.all(8), child: BackButton()) : null,
      title: StaticLayer(
        overflow: const EdgeInsets.all(10),
        child: Text(title, style: lobbyHeading(context, 28, color: lobby.panelAccent).copyWith(letterSpacing: 0.6)),
      ),
    );
  }
}

/// A card on the lobby scene: deep translucent green, thin gold border.
///
/// Rendered once into a [StaticLayer] (again only while its content or ink
/// changes), so its blurred shadow and text shadows are not redrawn on every
/// frame of the leaves behind it.
class LobbyPanel extends StatelessWidget {
  const LobbyPanel({super.key, required this.child, this.padding = EdgeInsets.zero, this.radius = 22, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: lobby.panelBorder, width: 1.1),
    );
    return StaticLayer(
      overflow: const EdgeInsets.fromLTRB(30, 30, 30, 40),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(lobby.panelFill, const Color(0xFFFFFFFF), 0.06)!, lobby.panelFill],
          ),
          shadows: [
            BoxShadow(
              color: lobby.textShadow.withValues(alpha: lobby.textShadow.a * 0.6),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashColor: lobby.panelAccent.withValues(alpha: 0.18),
            highlightColor: lobby.panelAccent.withValues(alpha: 0.08),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
