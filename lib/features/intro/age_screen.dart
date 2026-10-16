import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/brand.dart';
import '../../app/theme.dart';
import '../../data/age_group.dart';
import '../common/lobby_background.dart';
import '../common/lobby_chrome.dart';
import '../home/widgets/lobby_buttons.dart';

/// The neutral age screen (Google Play Families policy, mixed audience),
/// shown once at first launch between the logo and the lobby.
///
/// It asks only the birth year: first the decade, then the year, with
/// nothing chosen in advance and no hint of what the answer is for. The
/// answer becomes an [AgeGroup] for [onAnswered]; the year itself is not
/// kept.
class AgeScreen extends StatefulWidget {
  const AgeScreen({super.key, required this.onAnswered, this.now = DateTime.now});

  final ValueChanged<AgeGroup> onAnswered;

  /// The clock (tests pin the current year).
  final DateTime Function() now;

  /// Decades offered, newest first, down to the 1930s; "Earlier" covers the
  /// rest.
  static const int oldestDecade = 1930;

  @override
  State<AgeScreen> createState() => _AgeScreenState();
}

class _AgeScreenState extends State<AgeScreen> {
  late final int _currentYear = widget.now().year;

  /// The decade picked (its first year), or null on the decade step.
  int? _decade;

  /// The birth year picked; [_earlierYear] for "Earlier".
  int? _year;
  bool _submitted = false;

  static const int _earlierYear = AgeScreen.oldestDecade - 1;

  List<int> get _decades => [
    for (var decade = _currentYear - _currentYear % 10; decade >= AgeScreen.oldestDecade; decade -= 10) decade,
  ];

  List<int> _yearsOf(int decade) => [for (var year = decade; year <= math.min(decade + 9, _currentYear); year++) year];

  void _submit() {
    final year = _year;
    if (year == null || _submitted) return;
    _submitted = true;
    widget.onAnswered(AgeGroup.fromBirthYear(year, currentYear: _currentYear));
  }

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    final decade = _decade;
    final choices = decade == null
        ? [
            for (final d in _decades)
              _Choice(
                label: '${d}s',
                selected: false,
                onTap: () => setState(() {
                  _decade = d;
                  _year = null;
                }),
              ),
            _Choice(
              label: 'Earlier',
              semanticLabel: 'Before ${AgeScreen.oldestDecade}',
              selected: _year == _earlierYear,
              onTap: () => setState(() => _year = _earlierYear),
            ),
          ]
        : [
            for (final year in _yearsOf(decade))
              _Choice(label: '$year', selected: _year == year, onTap: () => setState(() => _year = year)),
            _Choice(
              label: 'Back',
              icon: Icons.arrow_back_rounded,
              semanticLabel: 'Back to the decades',
              selected: false,
              onTap: () => setState(() {
                _decade = null;
                _year = null;
              }),
            ),
          ];
    return Scaffold(
      backgroundColor: lobby.baseFallback.last,
      body: LobbyBackground(
        variant: LobbySceneVariant.subScreen,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: math.max(0, constraints.maxHeight - 40)),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LobbyPanel(
                          padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
                          child: Column(
                            children: [
                              Semantics(
                                header: true,
                                child: Text(
                                  'What year were you born?',
                                  textAlign: TextAlign.center,
                                  style: lobbyHeading(context, 26, color: lobby.panelAccent),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                decade == null ? 'Choose the decade, then the year.' : '${decade}s',
                                textAlign: TextAlign.center,
                                style: displayText(16, color: lobby.panelMuted, weight: FontWeight.w500),
                              ),
                              const SizedBox(height: 18),
                              _ChoiceGrid(children: choices),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Only once a year is picked; the space is kept so
                        // nothing moves.
                        SizedBox(
                          height: 62,
                          child: _year == null
                              ? null
                              : LobbyPrimaryButton(
                                  key: const ValueKey('age-continue'),
                                  label: 'Continue',
                                  height: 58,
                                  onPressed: _submit,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three choices per row, equal widths.
class _ChoiceGrid extends StatelessWidget {
  const _ChoiceGrid({required this.children});

  final List<Widget> children;

  static const int _columns = 3;
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var row = 0; row * _columns < children.length; row++) ...[
        if (row > 0) const SizedBox(height: _gap),
        Row(
          children: [
            for (var column = 0; column < _columns; column++) ...[
              if (column > 0) const SizedBox(width: _gap),
              Expanded(
                child: row * _columns + column < children.length
                    ? children[row * _columns + column]
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ],
    ],
  );
}

/// One decade or year: fine gold rim, filled and brighter when chosen.
class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap, this.semanticLabel, this.icon});

  final String label;
  final String? semanticLabel;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    final radius = BorderRadius.circular(14);
    final color = selected ? lobby.panelAccent : lobby.panelText;
    final style = displayText(18, color: color, weight: selected ? FontWeight.w700 : FontWeight.w500);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: selected ? lobby.panelAccent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: selected ? lobby.panelAccent : lobby.panelBorder.withValues(alpha: 0.7),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashColor: lobby.panelAccent.withValues(alpha: 0.18),
            highlightColor: lobby.panelAccent.withValues(alpha: 0.08),
            child: SizedBox(
              height: 48,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: icon == null
                        ? Text(label, maxLines: 1, style: style)
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: 18, color: color),
                              const SizedBox(width: 4),
                              Text(label, maxLines: 1, style: style),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
