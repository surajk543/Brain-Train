import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/app_services.dart';
import '../../app/theme.dart';
import '../common/lobby_background.dart';
import '../common/lobby_chrome.dart';
import '../common/static_layer.dart';

/// Sound, vibration and the app version. Nothing else.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final lobby = LobbyTheme.of(context);
    return Scaffold(
      backgroundColor: lobby.baseFallback.last,
      extendBodyBehindAppBar: true,
      appBar: const LobbyAppBar(title: 'Settings'),
      body: LobbyBackground(
        variant: LobbySceneVariant.subScreen,
        child: SafeArea(
          child: ListenableBuilder(
            listenable: settings,
            builder: (context, _) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                  children: [
                    LobbyPanel(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          _SettingSwitch(
                            icon: Icons.volume_up_rounded,
                            title: 'Sound',
                            value: settings.sound,
                            onChanged: settings.setSound,
                          ),
                          Divider(
                            height: 1,
                            indent: 64,
                            endIndent: 18,
                            color: lobby.panelBorder.withValues(alpha: 0.35),
                          ),
                          _SettingSwitch(
                            icon: Icons.vibration_rounded,
                            title: 'Vibration',
                            value: settings.haptics,
                            onChanged: settings.setHaptics,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, snapshot) {
                        final info = snapshot.data;
                        return StaticLayer(
                          overflow: const EdgeInsets.all(6),
                          child: Text(
                            info == null ? '' : 'Brain Train · Version ${info.version} (${info.buildNumber})',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: lobby.panelMuted,
                              fontSize: 13,
                              letterSpacing: 0.3,
                              shadows: [Shadow(color: lobby.textShadow, blurRadius: 4)],
                            ),
                          ),
                        );
                      },
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
  const _SettingSwitch({required this.icon, required this.title, required this.value, required this.onChanged});

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      secondary: Icon(icon, color: lobby.panelAccent),
      title: Text(title, style: lobbyHeading(context, 19, weight: FontWeight.w600)),
      value: value,
      onChanged: onChanged,
    );
  }
}
