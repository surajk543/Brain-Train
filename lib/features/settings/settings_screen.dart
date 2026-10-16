import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/app_services.dart';
import '../../app/theme.dart';
import '../common/lobby_background.dart';
import '../common/lobby_chrome.dart';
import '../common/static_layer.dart';

/// Sound, vibration and the app version. Nothing else, except "Privacy
/// choices" (Google's privacy options form) where the consent SDK requires
/// that entry point (EEA/UK); hidden everywhere else.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final settings = services.settings;
    final ads = services.ads;
    final lobby = LobbyTheme.of(context);
    return Scaffold(
      backgroundColor: lobby.baseFallback.last,
      extendBodyBehindAppBar: true,
      appBar: const LobbyAppBar(title: 'Settings'),
      body: LobbyBackground(
        variant: LobbySceneVariant.subScreen,
        child: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([settings, ads]),
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
                          if (ads.privacyOptionsRequired) ...[
                            Divider(
                              height: 1,
                              indent: 64,
                              endIndent: 18,
                              color: lobby.panelBorder.withValues(alpha: 0.35),
                            ),
                            _SettingLink(
                              icon: Icons.privacy_tip_outlined,
                              title: 'Privacy choices',
                              onTap: () => ads.openPrivacyOptions(),
                            ),
                          ],
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      leading: Icon(icon, color: lobby.panelAccent),
      title: Text(title, style: lobbyHeading(context, 19, weight: FontWeight.w600)),
      trailing: Icon(Icons.chevron_right_rounded, color: lobby.panelAccent),
      onTap: onTap,
    );
  }
}
