import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/motion_tokens.dart';
import '../../core/app_config.dart';
import '../../core/platform_info.dart';
import '../../personal/extractor_backend.dart';
import '../../personal/personal_tools_notifier.dart';
import '../../shared/widgets/ui_kit.dart';
import '../downloads/download_providers.dart' show extractorRunningDownloadsProvider;
import '../library/library_notifier.dart';
import '../music_player/resume_after_other_apps.dart';
import '../online/online_screen.dart' show confirmClearYouTubeData;
import '../online/online_settings.dart';
import '../online/online_web_view.dart' show onlineDataClearerProvider;
import 'settings_notifier.dart';
import 'theme_mode_setting.dart';
import 'user_name_setting.dart';

const String _appVersion = '1.0.0';

/// Width of the leading slot on every row, so all row titles line up with the
/// card heading text (16 gutter + 32 slot + 12 gap = 60). Compact: 32 dp
/// icons, rows stay at least 48 dp tall.
const double _leadingSlot = 32;
const double _rowTextInset = AppSpacing.lg16 + _leadingSlot + AppSpacing.md12;

/// Corner radius of the 32 dp tiles (card headings, app identity): the tile
/// radius of DESIGN.md 7.1.
const BorderRadius _tileRadius = BorderRadius.all(Radius.circular(AppSpacing.radiusThumb));

/// Space between two cards. The card headings carry the hierarchy, so there
/// are no separate group labels above the cards.
const double _cardGap = AppSpacing.lg16;

/// Row titles: the body role a step heavier (app strings, so Poppins).
TextStyle _rowTitleStyle(AppTextStyles type) => type.body.copyWith(fontWeight: FontWeight.w500);

/// Row and heading explanations: the metadata role one size down (13).
TextStyle _subtitleStyle(AppTextStyles type) => type.metadata.copyWith(fontSize: 13, height: 18 / 13);

/// Rows: ~10 dp above and below the text, one density step tighter.
const double _rowVerticalPadding = 10;
const VisualDensity _rowDensity = VisualDensity(vertical: -2);

/// Settings, opened from the gear in the Home header: one card each for
/// appearance, playback, YouTube, downloads, privacy and app info.
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
            style: context.typography.sectionTitle,
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
            const EntranceFade(index: 1, child: _YouCard()),
            const SizedBox(height: _cardGap),
            const EntranceFade(index: 1, child: _AppearanceCard()),
            const SizedBox(height: _cardGap),
            const EntranceFade(index: 2, child: _PlaybackCard()),
            const SizedBox(height: _cardGap),
            const EntranceFade(index: 3, child: _OnlineCard()),
            if (showPersonalTools) ...const [
              SizedBox(height: _cardGap),
              _PersonalToolsCard(),
            ],
            const SizedBox(height: _cardGap),
            const EntranceFade(index: 4, child: _PrivacyCard()),
            const SizedBox(height: _cardGap),
            const EntranceFade(index: 5, child: _AboutCard()),
          ],
        ),
      ),
    );
  }
}

/// The masthead: "Settings" in the display role (one line, scaled down
/// rather than clipped at large text) and what is in here.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final type = context.typography;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs4),
      child: EntranceFade(
        child: HeroBand(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('Settings', style: type.display, maxLines: 1),
                ),
              ),
              const SizedBox(height: AppSpacing.xs4),
              Text('Look, playback, YouTube, downloads and your privacy.', style: type.metadata),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Groups
// ---------------------------------------------------------------------------

/// Settings → You: the name Home greets with. Tap opens [_NameDialog].
class _YouCard extends ConsumerWidget {
  const _YouCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(userNameProvider);
    return _SettingsCard(
      children: [
        const _CardHeading(
          icon: Icons.person_rounded,
          title: 'You',
          subtitle: 'Kept on this phone only.',
        ),
        const _CardDivider.underHeading(),
        _NavRow(
          key: const ValueKey('settings_user_name'),
          icon: Icons.badge_outlined,
          title: 'Your name',
          subtitle: name.isEmpty ? 'Not set. Home says just नमस्ते.' : name,
          trailingIcon: Icons.edit_rounded,
          onTap: () async {
            final result = await showDialog<String>(
              context: context,
              builder: (_) => _NameDialog(initial: name),
            );
            if (result != null) ref.read(userNameProvider.notifier).set(result);
          },
        ),
      ],
    );
  }
}

/// Name editor: returns the new name, '' for Clear, or null for dismiss.
class _NameDialog extends StatefulWidget {
  final String initial;

  const _NameDialog({required this.initial});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(UserNameNotifier.normalize(_text.text));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your name'),
      content: TextField(
        key: const ValueKey('user_name_field'),
        controller: _text,
        autofocus: true,
        maxLength: UserNameNotifier.maxLength,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'How Home greets you'),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          key: const ValueKey('user_name_clear'),
          onPressed: () => Navigator.of(context).pop(''),
          child: const Text('Clear'),
        ),
        FilledButton(
          key: const ValueKey('user_name_save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Settings → Appearance: follow the phone (the default), always dark, always
/// light or Bijuli Classic ([appearanceSettingProvider]).
class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  static const List<(AppearanceChoice, IconData, String, String)> _options = [
    (AppearanceChoice.system, Icons.brightness_auto_rounded, 'System', 'Dark or light, the same as your phone.'),
    (AppearanceChoice.dark, Icons.dark_mode_rounded, 'Dark', 'Always dark.'),
    (AppearanceChoice.light, Icons.light_mode_rounded, 'Light', 'Always light.'),
    (AppearanceChoice.classic, Icons.bolt_outlined, 'Bijuli Classic', 'The original lime-on-violet look. Always dark.'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appearanceSettingProvider);
    final type = context.typography;

    return _SettingsCard(
      children: [
        const _CardHeading(
          icon: Icons.palette_rounded,
          title: 'Appearance',
          subtitle: 'How MediaHub looks. The player stays dark either way.',
        ),
        const _CardDivider.underHeading(),
        RadioGroup<AppearanceChoice>(
          groupValue: mode,
          onChanged: (value) {
            if (value != null) ref.read(appearanceSettingProvider.notifier).set(value);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, (value, icon, title, subtitle)) in _options.indexed) ...[
                if (i > 0) const _CardDivider.betweenRows(),
                RadioListTile<AppearanceChoice>(
                  key: ValueKey('appearance_${value.name}'),
                  value: value,
                  controlAffinity: ListTileControlAffinity.trailing,
                  contentPadding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.md12, 0),
                  minVerticalPadding: _rowVerticalPadding,
                  visualDensity: _rowDensity,
                  horizontalTitleGap: AppSpacing.md12,
                  secondary: _RowIcon(icon),
                  title: Text(title, style: _rowTitleStyle(type)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle, style: _subtitleStyle(type)),
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

class _PlaybackCard extends ConsumerWidget {
  const _PlaybackCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumeOnReconnect = ref.watch(resumeOnHeadphonesReconnectProvider);
    final resumeNotifier = ref.read(resumeOnHeadphonesReconnectProvider.notifier);
    // Android only: on an iPhone the system itself says when music may come back.
    final showOtherApps = PlatformInfo.isAndroid;
    final resumeAfterOtherApps = showOtherApps && ref.watch(resumeAfterOtherAppsProvider);

    return _SettingsCard(
      children: [
        _CardHeading(
          icon: Icons.headphones_rounded,
          title: 'Audio & headset',
          subtitle: showOtherApps
              ? 'How playback reacts to your headphones and other apps.'
              : 'How playback reacts to your headphones.',
        ),
        const _CardDivider.underHeading(),
        _SwitchRow(
          icon: Icons.restart_alt_rounded,
          title: 'Resume when headphones reconnect',
          subtitle: 'Picks up where you left off if they reconnect within 10 minutes of being disconnected.',
          value: resumeOnReconnect,
          onChanged: (_) => resumeNotifier.toggle(),
        ),
        if (showOtherApps) ...[
          const _CardDivider.betweenRows(),
          _SwitchRow(
            icon: Icons.music_note_rounded,
            title: 'Resume after other apps',
            subtitle: 'Plays your music again when another app stops playing, within 30 minutes.',
            value: resumeAfterOtherApps,
            onChanged: (v) => ref.read(resumeAfterOtherAppsProvider.notifier).set(v),
          ),
        ],
      ],
    );
  }
}

/// Settings → Online: the YouTube tab's background play, auto picture-in-picture,
/// ad blocking and a way to forget its cookies and cache.
class _OnlineCard extends ConsumerWidget {
  const _OnlineCard();

  Future<void> _clearData(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirmClearYouTubeData(context);
    if (!ok) return;
    await ref.read(onlineDataClearerProvider)();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('YouTube data cleared')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final background = ref.watch(onlineBackgroundPlayProvider);
    final autoPip = ref.watch(onlineAutoPipProvider);
    final blockAds = ref.watch(onlineBlockAdsProvider);

    return _SettingsCard(
      children: [
        const _CardHeading(
          icon: Icons.smart_display_rounded,
          title: 'Online',
          subtitle: 'YouTube in the Online tab.',
        ),
        const _CardDivider.underHeading(),
        _SwitchRow(
          icon: Icons.play_circle_outline_rounded,
          title: 'Background play',
          subtitle: 'Keeps the sound going with the screen off or while you use another app.',
          value: background,
          onChanged: (v) => ref.read(onlineBackgroundPlayProvider.notifier).set(v),
        ),
        const _CardDivider.betweenRows(),
        _SwitchRow(
          icon: Icons.picture_in_picture_alt_rounded,
          title: 'Auto picture-in-picture',
          subtitle: 'Shows the video in a small window when you leave the app while it plays.',
          value: autoPip,
          onChanged: (v) => ref.read(onlineAutoPipProvider.notifier).set(v),
        ),
        const _CardDivider.betweenRows(),
        // On by default. A change opens the Online tab's page again.
        _SwitchRow(
          icon: Icons.block_rounded,
          title: onlineBlockAdsTitle,
          subtitle: onlineBlockAdsSubtitle,
          value: blockAds,
          onChanged: (v) => ref.read(onlineBlockAdsProvider.notifier).set(v),
        ),
        const _CardDivider.betweenRows(),
        // Signing in happens in the Online tab (More options, then Sign in to
        // YouTube); Google may still refuse an app's web view for some
        // accounts, and the row says so.
        const _InfoRow(
          icon: Icons.account_circle_rounded,
          title: youTubeSignInSettingsTitle,
          body: youTubeSignInSettingsBody,
        ),
        const _CardDivider.betweenRows(),
        _NavRow(
          icon: Icons.delete_sweep_rounded,
          title: 'Clear YouTube data',
          subtitle: clearYouTubeDataSettingsSubtitle(),
          trailingIcon: Icons.chevron_right_rounded,
          onTap: () => _clearData(context, ref),
        ),
      ],
    );
  }
}

class _PersonalToolsCard extends ConsumerWidget {
  const _PersonalToolsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = context.typography;
    final personalState = ref.watch(personalToolsProvider);
    final personalNotifier = ref.read(personalToolsProvider.notifier);
    final status = personalState.updateStatus;
    // yt-dlp's files must not be replaced while a web link download runs them.
    final downloadsRunning = ref.watch(extractorRunningDownloadsProvider) > 0;
    final canChange = !personalState.isUpdating && !downloadsRunning;
    void startUpdate() => personalNotifier.updateYtDlp();
    void startReset() => personalNotifier.resetYtDlp();

    return _SettingsCard(
      children: [
        const _CardHeading(
          icon: Icons.link_rounded,
          accent: true,
          title: 'Personal tools',
          subtitle: 'Save public videos and music from a web link.',
        ),
        const _CardDivider.underHeading(),
        _SwitchRow(
          icon: Icons.download_for_offline_rounded,
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
                    const _CardDivider.betweenRows(),
                    ListTile(
                      minVerticalPadding: _rowVerticalPadding,
                  visualDensity: _rowDensity,
                      contentPadding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.md12, 0),
                      horizontalTitleGap: AppSpacing.md12,
                      leading: const _RowIcon(Icons.memory_rounded),
                      title: Text('yt-dlp engine version', style: _rowTitleStyle(type)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          // "2026.11.10 · Updated today": MediaHub updates yt-dlp by itself.
                          personalState.versionLine(),
                          style: type.tabularFigures,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                              enabled: canChange,
                              label: 'Update yt-dlp engine',
                              onTap: canChange ? startUpdate : null,
                              excludeSemantics: true,
                              child: FilledButton.tonal(
                                key: const ValueKey('settings_ytdlp_update'),
                                onPressed: canChange ? startUpdate : null,
                                child: const Text('Update'),
                              ),
                            ),
                    ),
                    if (downloadsRunning && !personalState.isUpdating)
                      const _UpdateStatus(
                        key: ValueKey('settings_ytdlp_busy'),
                        text: 'Web link downloads are running. Update when they finish.',
                        updating: true,
                      )
                    else if (status != null)
                      _UpdateStatus(
                        text: status,
                        updating: personalState.isUpdating,
                        failed: personalState.updateFailed,
                      ),
                    // Way back if an update ever breaks downloads (no need to clear app storage).
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.sm8, 0, AppSpacing.sm8, AppSpacing.sm8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const ValueKey('settings_ytdlp_reset'),
                          onPressed: canChange ? startReset : null,
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
    final isIOS = PlatformInfo.isIOS;

    return _SettingsCard(
      children: [
        const _CardHeading(
          icon: Icons.shield_rounded,
          title: 'Privacy & permissions',
          subtitle: 'What MediaHub uses, in plain words.',
        ),
        const _CardDivider.underHeading(),
        // The iPhone app reads nothing else on the phone: its library is
        // what you download in MediaHub.
        _InfoRow(
          icon: Icons.library_music_rounded,
          title: 'Your music and videos',
          body: isIOS
              ? 'Only the ones you download in MediaHub. MediaHub never uploads them.'
              : 'To find and play them. MediaHub never uploads them.',
        ),
        const _InfoRow(
          icon: Icons.public_rounded,
          title: 'The internet',
          body: 'Only for YouTube in the Online tab, streaming and downloads you start yourself.',
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
            body: 'MediaHub has no account of its own and syncs nothing. A YouTube sign-in '
                'in the Online tab stays on this phone. A phone-to-phone transfer to your '
                'next phone brings your library and downloads along.',
          )
        else
          const _PromiseNote(
            title: 'No accounts, no tracking',
            body: 'MediaHub never uploads your files (your iPhone\'s own iCloud backup may include them).',
          ),
        const _CardDivider.betweenRows(),
        _NavRow(
          icon: Icons.app_settings_alt_rounded,
          title: 'App permissions',
          subtitle: isIOS
              ? 'See or change what MediaHub may use, in iPhone Settings.'
              : 'See or change what MediaHub may use, in your phone\'s settings.',
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
          SnackBar(
            content: Text(
              PlatformInfo.isIOS ? 'Could not open iPhone Settings.' : 'Could not open your phone\'s settings.',
            ),
          ),
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
          icon: Icons.bug_report_rounded,
          title: 'Diagnostics log',
          subtitle: 'Recent app events (playback, downloads, network), handy when something goes wrong.',
          onTap: () {
            context.push('/diagnostics');
          },
        ),
        const _CardDivider.betweenRows(),
        _NavRow(
          icon: Icons.description_rounded,
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

/// Card title row: a tonal icon tile, the title and a one-line explanation.
class _CardHeading extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  /// Draws the glyph in the accent (Ice) instead of the brand primary.
  final bool accent;

  const _CardHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.md12, AppSpacing.lg16, AppSpacing.md12),
      child: Row(
        children: [
          _IconTile(icon: icon, color: accent ? palette.accent : palette.primary),
          const SizedBox(width: AppSpacing.md12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: type.sectionTitle),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: _subtitleStyle(type)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 32 dp tonal tile ([AppPalette.primaryContainer]) holding a [color] glyph.
class _IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconTile({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _leadingSlot,
      height: _leadingSlot,
      decoration: BoxDecoration(
        color: context.palette.primaryContainer,
        borderRadius: _tileRadius,
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}

/// Plain row icon centred in the same 32 dp slot as the heading tile.
class _RowIcon extends StatelessWidget {
  final IconData icon;

  const _RowIcon(this.icon);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _leadingSlot,
      child: Center(child: Icon(icon, size: 20, color: context.palette.textSecondary)),
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

/// Toggle row with the same leading icon slot as the other rows, so every
/// row in a card starts its text on one column.
class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final type = context.typography;
    return SwitchListTile(
      contentPadding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.md12, 0),
      minVerticalPadding: _rowVerticalPadding,
      visualDensity: _rowDensity,
      horizontalTitleGap: AppSpacing.md12,
      secondary: _RowIcon(icon),
      controlAffinity: ListTileControlAffinity.trailing,
      title: Text(title, style: _rowTitleStyle(type)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(subtitle, style: _subtitleStyle(type)),
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
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailingIcon = Icons.chevron_right_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
    return ListTile(
      minVerticalPadding: _rowVerticalPadding,
      visualDensity: _rowDensity,
      horizontalTitleGap: AppSpacing.md12,
      leading: _RowIcon(icon),
      title: Text(title, style: _rowTitleStyle(type)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(subtitle, style: _subtitleStyle(type)),
      ),
      trailing: Icon(trailingIcon, color: palette.textMuted),
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
    final type = context.typography;
    return ListTile(
      minVerticalPadding: AppSpacing.sm8,
      visualDensity: _rowDensity,
      horizontalTitleGap: AppSpacing.md12,
      leading: _RowIcon(icon),
      title: Text(title, style: _rowTitleStyle(type)),
      subtitle: Text(body, style: _subtitleStyle(type)),
    );
  }
}

/// Tonal call-out: the things MediaHub never does. The wording is chosen per
/// platform by the caller so it only promises what that platform delivers.
class _PromiseNote extends StatelessWidget {
  final String title;
  final String body;

  const _PromiseNote({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
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
            color: palette.primaryContainer,
            borderRadius: BorderRadius.circular(AppSpacing.radiusThumb),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.verified_user_rounded, size: 22, color: palette.primary),
              ),
              const SizedBox(width: AppSpacing.md12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: type.bodyStrong),
                    const SizedBox(height: 2),
                    Text(body, style: type.metadata),
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

  /// The app icon in miniature (DESIGN.md 7.16): the near-black-to-wine
  /// diagonal with the crimson play-bolt, the same in every theme.
  static const LinearGradient _iconField = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0B0B0D), Color(0xFF4A0F24)],
  );
  static const Color _iconGlyph = Color(0xFFCC324C);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg16),
      child: MergeSemantics(
        child: Row(
          children: [
            Container(
              width: _leadingSlot,
              height: _leadingSlot,
              decoration: BoxDecoration(
                gradient: _iconField,
                borderRadius: _tileRadius,
              ),
              child: const Icon(Icons.play_arrow_rounded, size: 22, color: _iconGlyph),
            ),
            const SizedBox(width: AppSpacing.md12),
            // The name gets the whole width; the version and the pill share
            // the line under it and wrap at large text instead of squeezing
            // the name.
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      AppConfig.appName,
                      style: type.sectionTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: AppSpacing.sm8,
                    runSpacing: AppSpacing.xs4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Version $_appVersion', style: type.tabularFigures),
                      const PillTag(text: 'Family use', icon: Icons.people_outline_rounded),
                    ],
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
  final bool failed;

  const _UpdateStatus({super.key, required this.text, required this.updating, this.failed = false});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
    final color = failed
        ? palette.error
        : updating
            ? palette.textSecondary
            : palette.success;
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
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: AppSpacing.sm8),
            Expanded(
              child: SelectionArea(
                child: Text(
                  text,
                  style: type.metadata.copyWith(color: color),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
