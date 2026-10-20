import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/app_services.dart';
import '../../app/theme.dart';
import '../../app/typography.dart';
import '../common/lobby_background.dart';
import '../common/lobby_chrome.dart';

/// Settings (redesign 1.1.0, reference board): one dark translucent panel
/// with a fine gold rim over the garden: a header (gear, "Settings", close),
/// the Sound Effects, Music and Vibration switches and the app version.
/// Nothing else, except "Privacy choices" (Google's privacy options form)
/// where the consent SDK requires that entry point (EEA/UK); hidden
/// everywhere else. No theme choice: the game has one look, Night.
///
/// A route: the close button and Android back pop it.
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
          info == null ? '' : 'Tile Park · Version ${info.version} (${info.buildNumber})',
          textAlign: TextAlign.center,
          style: BrainTrainType.body(size: 13, color: lobby.panelMuted).copyWith(letterSpacing: 0.3),
        );
      },
    );
  }
}
