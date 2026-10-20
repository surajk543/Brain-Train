import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_update_controller.dart';
import '../../../app/brand.dart';
import '../../../app/theme.dart';
import '../../../content/app_update_config.dart';
import '../../common/static_layer.dart';
import '../../gameplay/widgets/premium_chrome.dart';

/// The lobby's update card over a scrim (docs/APP_UPDATES.md).
///
/// Optional update: "Update available" with Update and Later; Android back
/// is Later. Required update: "Update required" with Update only; nothing
/// closes it (no Later, the scrim takes every tap, back does nothing), so
/// Play, Continue and Levels cannot be reached.
///
/// Must sit inside the lobby's [LobbyBackground] (its frost). The card is
/// flattened by a [StaticLayer]: the fireflies and leaves behind it do not
/// redraw its shadows and borders every frame.
///
/// Built again by the lobby whenever [controller] changes.
class LobbyUpdateCard extends StatelessWidget {
  const LobbyUpdateCard({super.key, required this.controller, required this.prompt});

  final AppUpdateController controller;
  final AppUpdatePrompt prompt;

  static const String optionalTitle = 'Update available';
  static const String optionalBody = 'A new version of Tile Park is ready.';
  static const String requiredTitle = 'Update required';
  static const String requiredBody =
      'This version of Tile Park is no longer supported. Please update to keep playing.';
  static const String failedNote = "Couldn't open the store. Please update Tile Park from your app store.";

  /// Between the lobby and the card (also the frost's tint).
  static const Color scrim = Color(0x9C020D08);

  @override
  Widget build(BuildContext context) {
    final required = prompt.need == AppUpdateNeed.required;
    final title = required ? requiredTitle : optionalTitle;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !required) controller.later();
      },
      child: BlockSemantics(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ModalBarrier(dismissible: false, color: scrim),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 380),
                          // Outside the entrance scale: re-rendered while it
                          // runs, then a single image.
                          child: StaticLayer(
                            overflow: const EdgeInsets.fromLTRB(44, 40, 44, 56),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.9, end: 1),
                              duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                              child: Semantics(
                                scopesRoute: true,
                                namesRoute: true,
                                explicitChildNodes: true,
                                label: title,
                                child: PremiumPanel(
                                  radius: 28,
                                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                                  frostTint: scrim,
                                  child: _content(title, required),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(String title, bool required) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const PremiumEmblem(icon: Icons.system_update_rounded),
      const SizedBox(height: 12),
      Text(title, textAlign: TextAlign.center, style: displayText(28, weight: FontWeight.w600)),
      const SizedBox(height: 10),
      Text(
        prompt.message ?? (required ? requiredBody : optionalBody),
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
      PremiumButton(
        key: const ValueKey('update-now'),
        label: 'Update',
        primary: true,
        expand: true,
        onPressed: controller.launching ? null : () => unawaited(controller.update()),
      ),
      if (controller.launchFailed)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Semantics(
            liveRegion: true,
            child: Text(
              failedNote,
              textAlign: TextAlign.center,
              style: displayText(14.5, color: BrandGold.light, weight: FontWeight.w500).copyWith(height: 1.3),
            ),
          ),
        ),
      if (!required) ...[
        const SizedBox(height: 4),
        PremiumButton(
          key: const ValueKey('update-later'),
          label: 'Later',
          quiet: true,
          expand: true,
          onPressed: controller.later,
        ),
      ],
    ],
  );
}
