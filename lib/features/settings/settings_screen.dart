import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/app_services.dart';
import '../../app/theme.dart';
import '../../app/typography.dart';
import '../../data/appearance.dart';
import '../common/lobby_background.dart';
import '../common/lobby_chrome.dart';

/// Settings (redesign 1.1.0, reference board): one dark translucent panel
/// with a fine gold rim over the garden: a header (gear, "Settings", close),
/// the Game Theme cards (Day, Night, System), the Sound Effects, Music and
/// Vibration switches and the app version. Nothing else, except "Privacy
/// choices" (Google's privacy options form) where the consent SDK requires
/// that entry point (EEA/UK); hidden everywhere else.
///
/// A route: the close button and Android back pop it. A theme card applies
/// its look at once (the app follows `SettingsRepository.appearance`).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final settings = services.settings;
    final ads = services.ads;
    final lobby = LobbyTheme.of(context);
    Widget divider() => Divider(height: 1, thickness: 1, color: lobby.panelBorder.withValues(alpha: 0.3));
    return Scaffold(
      backgroundColor: lobby.baseFallback.last,
      body: LobbyBackground(
        variant: LobbySceneVariant.subScreen,
        child: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([settings, ads]),
            builder: (context, _) => Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    LobbyPanel(
                      radius: 24,
                      padding: const EdgeInsets.fromLTRB(18, 8, 8, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _Header(),
                          divider(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 16, 10, 16),
                            child: _ThemeChoice(
                              value: settings.appearance,
                              onChanged: (value) => unawaited(settings.setAppearance(value)),
                            ),
                          ),
                          divider(),
                          _SettingSwitch(
                            key: const ValueKey('settings-sound'),
                            icon: Icons.volume_up_rounded,
                            title: 'Sound Effects',
                            value: settings.sound,
                            onChanged: settings.setSound,
                          ),
                          divider(),
                          _SettingSwitch(
                            key: const ValueKey('settings-music'),
                            icon: Icons.music_note_rounded,
                            title: 'Music',
                            value: settings.music,
                            onChanged: settings.setMusic,
                          ),
                          divider(),
                          _SettingSwitch(
                            key: const ValueKey('settings-vibration'),
                            icon: Icons.vibration_rounded,
                            title: 'Vibration',
                            value: settings.haptics,
                            onChanged: settings.setHaptics,
                          ),
                          if (ads.privacyOptionsRequired) ...[
                            divider(),
                            _SettingLink(
                              icon: Icons.privacy_tip_outlined,
                              title: 'Privacy choices',
                              onTap: () => ads.openPrivacyOptions(),
                            ),
                          ],
                          divider(),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(0, 14, 10, 0),
                            child: _Version(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gold gear, "Settings" and the close button.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(Icons.settings_rounded, color: lobby.panelAccent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                'Settings',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BrainTrainType.heading(size: 28, color: lobby.panelText),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('settings-close'),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close_rounded, color: lobby.panelAccent, size: 28),
          ),
        ],
      ),
    );
  }
}

/// "Game Theme": Day, Night and System cards; the selected one has a gold
/// rim and a warm gold fill.
class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({required this.value, required this.onChanged});

  final AppAppearance value;
  final ValueChanged<AppAppearance> onChanged;

  static const List<(AppAppearance, String, IconData)> _choices = [
    (AppAppearance.day, 'Day', Icons.wb_sunny_outlined),
    (AppAppearance.night, 'Night', Icons.dark_mode_outlined),
    (AppAppearance.system, 'System', Icons.smartphone_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Game Theme', style: BrainTrainType.body(size: 15, color: lobby.panelText, weight: FontWeight.w600)),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, (appearance, label, icon)) in _choices.indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: _ThemeCard(
                    key: ValueKey('theme-${appearance.storageValue}'),
                    label: label,
                    icon: icon,
                    selected: appearance == value,
                    onTap: () => onChanged(appearance),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({super.key, required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: selected
          ? BorderSide(color: lobby.panelAccent, width: 1.8)
          : BorderSide(color: lobby.panelText.withValues(alpha: 0.28)),
    );
    final fill = selected
        ? [lobby.panelAccent.withValues(alpha: 0.34), lobby.panelAccent.withValues(alpha: 0.14)]
        : [const Color(0x2E2FA58A), const Color(0x1A0E5A48)];
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '$label theme',
      excludeSemantics: true,
      onTap: onTap,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: fill),
          shadows: selected ? [BoxShadow(color: lobby.panelAccent.withValues(alpha: 0.25), blurRadius: 10)] : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashColor: lobby.panelAccent.withValues(alpha: 0.2),
            highlightColor: lobby.panelAccent.withValues(alpha: 0.08),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 76),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 28, color: selected ? lobby.panelAccent : lobby.panelText.withValues(alpha: 0.9)),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BrainTrainType.body(
                        size: 13.5,
                        color: selected ? lobby.panelText : lobby.panelMuted,
                        weight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    return SwitchListTile(
      contentPadding: const EdgeInsets.fromLTRB(0, 2, 6, 2),
      secondary: Icon(icon, color: lobby.panelAccent),
      title: Text(title, style: BrainTrainType.body(size: 16, color: lobby.panelText, weight: FontWeight.w600)),
      value: value,
      onChanged: onChanged,
      // Reference: a green track with an ivory thumb when on.
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? BrainTrainColors.warmIvory : const Color(0xFFB9C7BE),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? const Color(0xFF3C9A55) : const Color(0x66021A14),
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? const Color(0xFF55B26C) : lobby.panelBorder,
      ),
    );
  }
}

/// A row that opens something (the privacy options form).
class _SettingLink extends StatelessWidget {
  const _SettingLink({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(0, 2, 10, 2),
      leading: Icon(icon, color: lobby.panelAccent),
      title: Text(title, style: BrainTrainType.body(size: 16, color: lobby.panelText, weight: FontWeight.w600)),
      trailing: Icon(Icons.chevron_right_rounded, color: lobby.panelAccent),
      onTap: onTap,
    );
  }
}

/// "Brain Train · Version 1.0.0 (7)".
class _Version extends StatelessWidget {
  const _Version();

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        return Text(
          info == null ? '' : 'Brain Train · Version ${info.version} (${info.buildNumber})',
          textAlign: TextAlign.center,
          style: BrainTrainType.body(size: 13, color: lobby.panelMuted).copyWith(letterSpacing: 0.3),
        );
      },
    );
  }
}
