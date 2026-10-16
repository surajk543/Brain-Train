import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The logo's own background colour.
const Color kBrandLogoBackground = Colors.white;

/// The Brain Train logo, shown after the studio intro while the game loads.
class BrandLogoScreen extends StatelessWidget {
  const BrandLogoScreen({super.key, this.loading = false, this.failed = false, this.onRetry});

  /// Shows a small progress indicator under the logo.
  final bool loading;

  /// Content could not load: shows a retry button instead.
  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
    child: Scaffold(
      backgroundColor: kBrandLogoBackground,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).shortestSide * 0.78, maxHeight: 360),
                child: Image.asset('assets/branding/brain_train_logo.jpg', semanticLabel: 'Brain Train'),
              ),
            ),
            const SizedBox(height: 32),
            if (failed) ...[
              const Text('Brain Train could not load its levels.', style: TextStyle(color: Color(0xFF1B2E5A))),
              TextButton(onPressed: onRetry, child: const Text('Try again')),
            ] else
              SizedBox(
                height: 48,
                child: loading
                    ? const Center(
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF1F3A8A)),
                        ),
                      )
                    : null,
              ),
          ],
        ),
      ),
    ),
  );
}
