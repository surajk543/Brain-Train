import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'premium_chrome.dart';

/// The trophy on the "Level complete!" card: loops while shown. The controller
/// is disposed with the widget, so the loop stops when the card closes. With
/// reduce-motion the last frame shows at once and nothing animates; if the file
/// cannot be loaded the static emblem takes its place.
class WinTrophy extends StatefulWidget {
  const WinTrophy({super.key, this.width = 210, @visibleForTesting this.assetName = asset});

  static const asset = 'assets/lottie/trophy_cup_rays.json';

  final double width;
  final String assetName;

  @override
  State<WinTrophy> createState() => _WinTrophyState();
}

class _WinTrophyState extends State<WinTrophy> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onLoaded(LottieComposition composition) {
    _controller.duration = composition.duration;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.width * 2 / 3;
    return ExcludeSemantics(
      child: SizedBox(
        width: widget.width,
        height: height,
        child: RepaintBoundary(
          child: Lottie.asset(
            widget.assetName,
            controller: _controller,
            onLoaded: _onLoaded,
            width: widget.width,
            height: height,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                const Center(child: PremiumEmblem(icon: Icons.emoji_events_rounded)),
          ),
        ),
      ),
    );
  }
}
