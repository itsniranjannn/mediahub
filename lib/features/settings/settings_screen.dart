import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/motion_tokens.dart';
import '../../core/app_config.dart';
import '../../core/platform_info.dart';
import '../../personal/extractor_backend.dart';
import '../../personal/personal_tools_notifier.dart';
import '../../shared/widgets/ui_kit.dart';
import '../library/library_notifier.dart';
import 'settings_notifier.dart';

const String _appVersion = '1.0.0';

/// Width of the leading slot on every row, so all row titles line up with the
/// card heading text (16 gutter + 40 slot + 12 gap = 68).
const double _leadingSlot = 40;
const double _rowTextInset = AppSpacing.lg16 + _leadingSlot + AppSpacing.md12;

/// Corner radius shared by the 40 dp icon tiles (card headings, app identity).
const BorderRadius _badgeRadius = BorderRadius.all(Radius.circular(AppSpacing.md12));

/// Space between two cards. The card headings carry the hierarchy, so there
/// are no separate group labels above the cards.
const double _cardGap = AppSpacing.xl20;

TextStyle get _rowTitleStyle => AppTypography.body.copyWith(fontWeight: FontWeight.w500);

/// Settings, opened from the gear in the Home header: one card each for
/// playback, downloads, privacy and app info.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Once the large "Settings" header has scrolled away, the app bar shows the title.
  static const double _titleThreshold = 44;

  final ScrollController _scroll = ScrollController();
  final ValueNotifier<bool> _showBarTitle = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    _showBarTitle.value = _scroll.offset > _titleThreshold;
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _showBarTitle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showPersonalTools = PlatformInfo.supportsWebLinkDownloader && kPersonalToolsEnabled;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<bool>(
          valueListenable: _showBarTitle,
          builder: (context, show, child) => AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: MotionTokens.duration(context, MotionTokens.feedback),
            curve: MotionTokens.easeOut,
            child: child,
          ),
          child: Text(
            'Settings',
            style: AppTypography.sectionTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      // Short, fixed list of cards: a plain scroll view keeps every group built.
      body: SingleChildScrollView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg16,
          0,
          AppSpacing.lg16,
          AppSpacing.xxxl32 + bottomInset,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Header(),
            const SizedBox(height: AppSpacing.xxl24),
            const _PlaybackCard(),
            if (showPersonalTools) ...const [
              SizedBox(height: _cardGap),
              _PersonalToolsCard(),
            ],
            const SizedBox(height: _cardGap),
            const _PrivacyCard(),
            const SizedBox(height: _cardGap),
            const _AboutCard(),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text('Settings', style: AppTypography.display)),
          const SizedBox(height: AppSpacing.xs4),
          Text('Playback, downloads and your privacy.', style: AppTypography.metadata),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Groups
// ---------------------------------------------------------------------------

class _PlaybackCard extends ConsumerWidget {
  const _PlaybackCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumeOnReconnect = ref.watch(resumeOnHeadphonesReconnectProvider);
    final resumeNotifier = ref.read(resumeOnHeadphonesReconnectProvider.notifier);

    return _SettingsCard(
      children: [
        const _CardHeading(
          icon: Icons.headphones_rounded,
          title: 'Audio & Headset',
          subtitle: 'How playback reacts to your headphones.',
        ),
        const _CardDivider.underHeading(),
        _SwitchRow(
          title: 'Resume when headphones reconnect',
          subtitle: 'Picks up where you left off if they reconnect within 10 minutes of being disconnected.',
          value: resumeOnReconnect,
          onChanged: (_) => resumeNotifier.toggle(),
        ),
      ],
    );
  }
}

class _PersonalToolsCard extends ConsumerWidget {
  const _PersonalToolsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personalState = ref.watch(personalToolsProvider);
    final personalNotifier = ref.read(personalToolsProvider.notifier);
    final status = personalState.updateStatus;
    void startUpdate() => personalNotifier.updateYtDlp();
    void startReset() => personalNotifier.resetYtDlp();

    return _SettingsCard(
      children: [
        const _CardHeading(
          icon: Icons.link_rounded,
          color: AppColors.accent,
          title: 'Personal tools',
          subtitle: 'Save public videos and music from a web link.',
        ),
        const _CardDivider.underHeading(),
        _SwitchRow(
          title: 'Enable web link downloader',
          subtitle: 'Personal use only. May break third-party service terms and is the user\'s own '
              'responsibility. Only public media without authentication is supported.',
          value: personalState.isEnabled,
          onChanged: (val) => personalNotifier.setEnabled(val),
        ),
        AnimatedSize(
          duration: MotionTokens.duration(context, MotionTokens.page),
          curve: MotionTokens.easeOut,
          alignment: Alignment.topCenter,
          child: personalState.isEnabled
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _CardDivider.betweenRows(hasLeadingIcon: false),
                    ListTile(
                      minVerticalPadding: AppSpacing.md12,
                      contentPadding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.md12, 0),
                      title: Text('yt-dlp engine version', style: _rowTitleStyle),
                      subtitle: Text(
                        personalState.ytDlpVersion.isEmpty ? 'Loading...' : personalState.ytDlpVersion,
                        style: AppTypography.tabularFigures,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: personalState.isUpdating
                          ? const SizedBox(
                              width: AppSpacing.minTouchTarget,
                              height: AppSpacing.minTouchTarget,
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    semanticsLabel: 'Updating yt-dlp',
                                  ),
                                ),
                              ),
                            )
                          // The visible label is just "Update"; screen readers get
                          // what is being updated. The tap action is kept on the node.
                          : Semantics(
                              button: true,
                              enabled: true,
                              label: 'Update yt-dlp engine',
                              onTap: startUpdate,
                              excludeSemantics: true,
                              child: FilledButton.tonal(
                                onPressed: startUpdate,
                                child: const Text('Update'),
                              ),
                            ),
                    ),
                    if (status != null) _UpdateStatus(text: status, updating: personalState.isUpdating),
                    // Way back if an update ever breaks downloads (no need to clear app storage).
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.sm8, 0, AppSpacing.sm8, AppSpacing.sm8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: personalState.isUpdating ? null : startReset,
                          icon: const Icon(Icons.restore_rounded, size: 18),
                          label: const Text('Use the built-in yt-dlp'),
                        ),
                      ),
                    ),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _PrivacyCard extends ConsumerWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Android keeps all app data out of Google cloud backup, but a phone-to-phone
    // transfer started by the user carries the library along
    // (AndroidManifest + data_extraction_rules.xml). iOS has no such opt-out
    // in this app, so the iPhone's own iCloud backup may include app files.
    final isAndroid = PlatformInfo.isAndroid;

    return _SettingsCard(
      children: [
        const _CardHeading(
          icon: Icons.shield_outlined,
          title: 'Privacy & permissions',
          subtitle: 'What MediaHub uses, in plain words.',
        ),
        const _CardDivider.underHeading(),
        const _InfoRow(
          icon: Icons.library_music_outlined,
          title: 'Your music and videos',
          body: 'To find and play them. MediaHub never uploads them.',
        ),
        const _InfoRow(
          icon: Icons.public_rounded,
          title: 'The internet',
          body: 'Only for searches, streaming and downloads you start yourself.',
        ),
        // iOS never asks for notification permission; its lock-screen
        // controls are not notifications.
        if (isAndroid)
          const _InfoRow(
            icon: Icons.notifications_none_rounded,
            title: 'Notifications',
            body: 'For player controls and download progress.',
          ),
        if (isAndroid)
          const _PromiseNote(
            title: 'No accounts, no tracking, no cloud backup',
            body: 'There is nothing to sign in to and nothing to sync. A phone-to-phone '
                'transfer to your next phone brings your library and downloads along.',
          )
        else
          const _PromiseNote(
            title: 'No accounts, no tracking',
            body: 'MediaHub never uploads your files (your iPhone\'s own iCloud backup may include them).',
          ),
        const _CardDivider.betweenRows(),
        _NavRow(
          icon: Icons.app_settings_alt_outlined,
          title: 'App permissions',
          subtitle: 'See or change what MediaHub may use, in your phone\'s settings.',
          trailingIcon: Icons.open_in_new_rounded,
          onTap: () => _openAppPermissions(context, ref),
        ),
      ],
    );
  }

  static Future<void> _openAppPermissions(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final permissions = ref.read(mediaPermissionServiceProvider);
    var opened = false;
    try {
      opened = await permissions.openSettings();
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not open your phone\'s settings.')),
        );
    }
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      children: [
        const _AppIdentity(),
        const _CardDivider.underHeading(),
        _NavRow(
          icon: Icons.bug_report_outlined,
          title: 'Diagnostics Log',
          subtitle: 'Recent app events (playback, downloads, network), handy when something goes wrong.',
          onTap: () {
            context.push('/diagnostics');
          },
        ),
        const _CardDivider.betweenRows(),
        _NavRow(
          icon: Icons.description_outlined,
          title: 'Open-source licenses',
          subtitle: 'Libraries used by MediaHub and their licenses.',
          onTap: () => showLicensePage(
            context: context,
            applicationName: AppConfig.appName,
            applicationVersion: _appVersion,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Building blocks
// ---------------------------------------------------------------------------

/// A [SurfaceCard] holding rows; clipped so row ripples follow the rounded corners.
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: SurfaceCard(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// Card title row: tinted icon badge, title and a one-line explanation.
class _CardHeading extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _CardHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg16),
      child: Row(
        children: [
          _IconBadge(icon: icon, color: color),
          const SizedBox(width: AppSpacing.md12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: AppTypography.sectionTitle),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTypography.metadata),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _leadingSlot,
      height: _leadingSlot,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: _badgeRadius,
      ),
      child: Icon(icon, size: 22, color: color),
    );
  }
}

/// Plain row icon centred in the same 40 dp slot as the heading badge.
class _RowIcon extends StatelessWidget {
  final IconData icon;

  const _RowIcon(this.icon);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _leadingSlot,
      child: Center(child: Icon(icon, size: 22, color: AppColors.textSecondary)),
    );
  }
}

/// Separators inside a card follow one rule on every card:
/// - full width under a card heading ([_CardDivider.underHeading]);
/// - between two sibling rows, indented to where the row text starts
///   ([_CardDivider.betweenRows]): 68 dp after the icon slot, or the 16 dp
///   gutter for rows without a leading icon.
///
/// Read-only [_InfoRow]s read as one block and are not separated.
class _CardDivider extends StatelessWidget {
  final double indent;

  const _CardDivider.underHeading() : indent = 0;

  const _CardDivider.betweenRows({bool hasLeadingIcon = true})
      : indent = hasLeadingIcon ? _rowTextInset : AppSpacing.lg16;

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, thickness: 1, indent: indent);
  }
}

/// Toggle row. No leading icon (the card heading carries it), so the text gets
/// the full card width on narrow phones.
class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.md12, 0),
      minVerticalPadding: AppSpacing.md12,
      title: Text(title, style: _rowTitleStyle),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(subtitle, style: AppTypography.metadata),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final IconData trailingIcon;
  final VoidCallback onTap;

  const _NavRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailingIcon = Icons.chevron_right_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minVerticalPadding: AppSpacing.md12,
      horizontalTitleGap: AppSpacing.md12,
      leading: _RowIcon(icon),
      title: Text(title, style: _rowTitleStyle),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(subtitle, style: AppTypography.metadata),
      ),
      trailing: Icon(trailingIcon, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}

/// Read-only explanation row (no tap target).
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoRow({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minVerticalPadding: AppSpacing.sm8,
      horizontalTitleGap: AppSpacing.md12,
      leading: _RowIcon(icon),
      title: Text(title, style: _rowTitleStyle),
      subtitle: Text(body, style: AppTypography.metadata),
    );
  }
}

/// Teal call-out: the things MediaHub never does. The wording is chosen per
/// platform by the caller so it only promises what that platform delivers.
class _PromiseNote extends StatelessWidget {
  final String title;
  final String body;

  const _PromiseNote({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg16,
        AppSpacing.sm8,
        AppSpacing.lg16,
        AppSpacing.lg16,
      ),
      child: MergeSemantics(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md12),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.verified_user_outlined, size: 22, color: AppColors.accent),
              ),
              const SizedBox(width: AppSpacing.md12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.bodyStrong),
                    const SizedBox(height: 2),
                    Text(body, style: AppTypography.metadata),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// App name and version: the heading of the About card.
class _AppIdentity extends StatelessWidget {
  const _AppIdentity();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg16),
      child: MergeSemantics(
        child: Row(
          children: [
            Container(
              width: _leadingSlot,
              height: _leadingSlot,
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: _badgeRadius,
              ),
              child: const Icon(Icons.play_arrow_rounded, size: 26, color: AppColors.onPrimary),
            ),
            const SizedBox(width: AppSpacing.md12),
            // Name on the left, pill pinned right. Both are loose-flexible so at
            // large text scales the name ellipsizes and the pill scales down
            // instead of the row overflowing.
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            AppConfig.appName,
                            style: AppTypography.sectionTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text('Version $_appVersion', style: AppTypography.tabularFigures),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm8),
                  const Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: PillTag(text: 'Family use', icon: Icons.people_outline_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Result line under the yt-dlp row: progress, success or failure. Shown in
/// full and selectable: a failure reason is only ever reported here.
class _UpdateStatus extends StatelessWidget {
  final String text;
  final bool updating;

  const _UpdateStatus({required this.text, required this.updating});

  @override
  Widget build(BuildContext context) {
    final failed = text.startsWith('Update failed') || text.startsWith('Reset failed');
    final color = failed
        ? AppColors.error
        : updating
            ? AppColors.textSecondary
            : AppColors.success;
    final icon = failed
        ? Icons.error_outline_rounded
        : updating
            ? Icons.sync_rounded
            : Icons.check_circle_outline_rounded;

    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.lg16, AppSpacing.lg16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: AppSpacing.sm8),
            Expanded(
              child: SelectionArea(
                child: Text(
                  text,
                  style: AppTypography.metadata.copyWith(color: color),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
