import 'package:brain_train/features/common/frosted_glass.dart';
import 'package:brain_train/features/common/static_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingPainter extends CustomPainter {
  _CountingPainter(this.color, this.paints);

  final Color color;
  final List<int> paints;

  @override
  void paint(Canvas canvas, Size size) {
    paints[0]++;
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CountingPainter old) => old.color != color;
}

/// Repaints every frame, next to (not inside) the static layer.
class _Spinner extends StatefulWidget {
  const _Spinner();

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _c,
    child: const SizedBox(width: 20, height: 20, child: ColoredBox(color: Colors.red)),
  );
}

void main() {
  testWidgets('a static layer paints its child once, and again only when the child changes', (tester) async {
    final paints = [0];
    Widget app(Color color) => MaterialApp(
      home: Stack(
        children: [
          StaticLayer(
            child: SizedBox(width: 100, height: 100, child: CustomPaint(painter: _CountingPainter(color, paints))),
          ),
          const Positioned(left: 150, top: 0, child: _Spinner()),
        ],
      ),
    );

    await tester.pumpWidget(app(Colors.green));
    final layer = tester.renderObject<RenderStaticLayer>(find.byType(StaticLayer));
    expect(paints[0], 1);
    expect(layer.hasImage, isTrue);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(paints[0], 1, reason: 'the animation next to it does not re-render the child');

    await tester.pumpWidget(app(Colors.blue));
    expect(paints[0], 2, reason: 'a changed child is rendered again');
    expect(layer.hasImage, isTrue);
  });

  testWidgets('frosted glass without a frost source paints just its child', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: FrostedGlass(
            borderRadius: BorderRadius.circular(12),
            child: const SizedBox(width: 80, height: 40, child: Text('Glass')),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Glass'), findsOneWidget);
  });
}
