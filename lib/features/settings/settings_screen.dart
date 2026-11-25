// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/motion_tokens.dart';
import '../../core/app_config.dart';
import '../../core/core_watermark.dart';
import '../../core/platform/backup_file_picker.dart';
import '../../core/platform_info.dart';
import '../../personal/extractor_backend.dart';
import '../../personal/personal_tools_notifier.dart';
import '../../shared/widgets/brand_marks.dart';
import '../../shared/widgets/choice_dialogs.dart';
import '../../shared/widgets/ui_kit.dart';
import '../downloads/download_providers.dart' show extractorRunningDownloadsProvider;
import '../library/library_notifier.dart';
import '../music_player/resume_after_other_apps.dart';
import '../online/online_screen.dart' show confirmClearYouTubeData;
import '../online/online_settings.dart';
import '../online/online_web_view.dart' show onlineDataClearerProvider;
import '../downloads/mobile_data_guard.dart';
import '../downloads/save_to_phone.dart';
import '../app_lock/app_lock.dart';
import '../music_player/equalizer/audio_effects.dart';
import '../music_player/equalizer/equalizer_sheet.dart';
import '../music_player/lyrics/lyrics_repository.dart';
import '../../core/platform/phone_media.dart';
import 'backup_restore.dart';
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

/// The groups of Settings. The top level lists them as compact rows; each
/// opens its own page ([SettingsSectionPage]) with the rows it holds.
enum SettingsSection {
  appearance('Appearance', Icons.palette_rounded),
  playback('Playback & audio', Icons.headphones_rounded),
  downloads('Downloads', Icons.download_rounded),
  online('Online', Icons.smart_display_rounded),
  privacy('Privacy & security', Icons.shield_rounded),
  backup('Backup', Icons.settings_backup_restore_rounded),
  about('About', Icons.info_rounded);

  const SettingsSection(this.title, this.icon);

  final String title;
  final IconData icon;

  static bool get _mobile => PlatformInfo.isAndroid || PlatformInfo.isIOS;
  static bool get _personalTools => PlatformInfo.supportsWebLinkDownloader && kPersonalToolsEnabled;

  /// Whether this platform has anything to show in the group.
  bool get isAvailable => this != SettingsSection.downloads || _mobile || _personalTools;

  /// The cards of the group's page, in order.
  List<Widget> cards() => switch (this) {
    SettingsSection.appearance => const [_YouCard(), _AppearanceCard()],
    SettingsSection.playback => const [_PlaybackCard()],
    SettingsSection.downloads => [
      if (_mobile) const _DownloadsDataCard(),
      if (_personalTools) const _PersonalToolsCard(),
    ],
    SettingsSection.online => const [_OnlineCard()],
    SettingsSection.privacy => [if (_mobile) const _AppLockCard(), const _PrivacyCard()],
    SettingsSection.backup => const [_BackupCard()],
    SettingsSection.about => const [_AboutCard()],
  };
}

/// Settings, opened from the gear in the Home header: a short list of
/// groups (one small row each) and the MediaHub footer.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Rows on the first card; the rest go on the second.
  static const Set<SettingsSection> _firstCard = {
    SettingsSection.appearance,
    SettingsSection.playback,
    SettingsSection.downloads,
    SettingsSection.online,
  };

  @override
  Widget build(BuildContext context) {
    final sections = SettingsSection.values.where((s) => s.isAvailable).toList();
    Widget card(Iterable<SettingsSection> group) {
      final rows = group.toList();
      return _SettingsCard(
        children: [
          for (final (i, s) in rows.indexed) ...[if (i > 0) const _CardDivider.betweenRows(), _SectionRow(section: s)],
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: Text('Settings', style: context.typography.screenTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
      bottomNavigationBar: const SettingsFooter(),
      body: _ReadableColumn(
        child: ListView(
          // The pinned footer takes the bottom inset; this only keeps the
          // last row clear of it.
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.xs4, AppSpacing.lg16, AppSpacing.lg16),
          children: [
            EntranceFade(child: card(sections.where(_firstCard.contains))),
            const SizedBox(height: AppSpacing.md12),
            EntranceFade(index: 1, child: card(sections.where((s) => !_firstCard.contains(s)))),
            const SizedBox(height: AppSpacing.md12),
            const EntranceFade(index: 2, child: SettingsLicencesLink()),
          ],
        ),
      ),
    );
  }
}

/// Landscape and tablets: one readable column, at most 640 dp, in the
/// middle. The safe-area insets (a camera cutout in landscape) go around it
/// once; the rows inside do not add them again (a ListTile pads itself).
class _ReadableColumn extends StatelessWidget {
  const _ReadableColumn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: false,
      child: MediaQuery.removePadding(
        context: context,
        removeLeft: true,
        removeRight: true,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: child),
        ),
      ),
    );
  }
}

/// One group's page: its cards under the group's name.
class SettingsSectionPage extends StatelessWidget {
  SettingsSectionPage({super.key, required SettingsSection section}) : sections = [section];

  /// Several groups on one page (tests that check rows of more than one).
  @visibleForTesting
  const SettingsSectionPage.combined(this.sections, {super.key});

  final List<SettingsSection> sections;

  static Route<void> route(SettingsSection section) => MaterialPageRoute<void>(
    settings: RouteSettings(name: 'settings/${section.name}'),
    builder: (_) => SettingsSectionPage(section: section),
  );

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final cards = [for (final s in sections) ...s.cards()];
    final title = sections.length == 1 ? sections.single.title : 'Settings';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: context.typography.sectionTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: _ReadableColumn(
        // Short, fixed list of cards: a plain scroll view keeps every row built.
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg16,
            AppSpacing.xs4,
            AppSpacing.lg16,
            AppSpacing.xxl24 + bottomInset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, c) in cards.indexed) ...[
                if (i > 0) const SizedBox(height: _cardGap),
                EntranceFade(index: i, child: c),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A top-level group row: tonal icon tile, the group's name, a one-line
/// summary of what is set, and a chevron.
class _SectionRow extends ConsumerWidget {
  const _SectionRow({required this.section});

  final SettingsSection section;

  String _summary(WidgetRef ref) {
    final mobile = SettingsSection._mobile;
    switch (section) {
      case SettingsSection.appearance:
        final mode = ref.watch(appearanceSettingProvider);
        final name = ref.watch(userNameProvider);
        final look = _AppearanceCard._options.firstWhere((o) => o.$1 == mode).$3;
        return name.isEmpty ? look : '$look · $name';
      case SettingsSection.playback:
        if (AudioEffects.supported && ref.watch(equalizerProvider.select((e) => e.enabled))) {
          return 'Equalizer on · ${ref.watch(equalizerProvider.select((e) => e.preset))}';
        }
        return AudioEffects.supported ? 'Headphones, equalizer and lyrics' : 'Headphones and lyrics';
      case SettingsSection.downloads:
        if (!mobile) return 'Web link downloader';
        final supported = ref.watch(_phoneMediaCapsProvider).value?.canSaveToPhone ?? false;
        final where = supported ? _SaveLocationRow._label(ref.watch(downloadSaveLocationProvider)) : 'Inside MediaHub';
        return 'Saved to: $where';
      case SettingsSection.online:
        return 'YouTube: background play, ads, sign-in';
      case SettingsSection.privacy:
        if (!mobile) return 'What MediaHub uses';
        return ref.watch(appLockProvider.select((l) => l.settings.enabled))
            ? 'App lock on · permissions'
            : 'App lock off · permissions';
      case SettingsSection.backup:
        return 'Save or restore your library';
      case SettingsSection.about:
        return 'Version $_appVersion';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
    return ListTile(
      key: ValueKey('settings_section_${section.name}'),
      minVerticalPadding: 8,
      visualDensity: _rowDensity,
      contentPadding: const EdgeInsets.fromLTRB(AppSpacing.md12, 0, AppSpacing.sm8, 0),
      horizontalTitleGap: AppSpacing.md12,
      leading: _IconTile(icon: section.icon, color: palette.primary),
      title: Text(section.title, style: _rowTitleStyle(type), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(_summary(ref), style: _subtitleStyle(type), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Icon(Icons.chevron_right_rounded, color: palette.textMuted),
      onTap: () => Navigator.of(context).push(SettingsSectionPage.route(section)),
    );
  }
}

/// The footer pinned to the bottom of Settings (the Scaffold's
/// bottomNavigationBar, so it never scrolls away): the author's signature
/// on the left, the launch-screen logo with the MediaHub wordmark and the
/// version on the right, a soft vertical rule between them.
/// [SettingsLicencesLink] (the OFL fonts and the packages require that
/// attribution) sits at the end of the list instead.
class SettingsFooter extends StatelessWidget {
  const SettingsFooter({super.key});

  static void openLicences(BuildContext context) => showLicensePage(
    context: context,
    applicationName: AppConfig.appName,
    applicationVersion: _appVersion,
    applicationIcon: const Padding(padding: EdgeInsets.all(AppSpacing.sm8), child: MediaHubLogo(size: 48)),
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const MediaHubWordmark(fontSize: 17),
            const SizedBox(height: 2),
            Text('v$_appVersion', style: AuthorMark.nameStyle(palette, fontSize: 10, color: palette.textMuted)),
          ],
        ),
        const SizedBox(width: AppSpacing.sm8 + 2),
        const MediaHubLogo(size: 32),
      ],
    );
    const signature = AuthorMark(nameSize: 25);

    return DecoratedBox(
      key: const ValueKey('settings_footer'),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.divider)),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color.alphaBlend(palette.primaryContainer.withValues(alpha: 0.35), palette.surface),
            palette.surface,
            palette.surface,
          ],
          stops: const [0, 0.55, 1],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl20, AppSpacing.sm8 + 2, AppSpacing.lg16, AppSpacing.sm8 + 2),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Narrow or large text: the signature over the brand.
                  final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
                  if (constraints.maxWidth < 310 * scale) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: signature),
                        const SizedBox(height: AppSpacing.xs4),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          heightFactor: 1,
                          child: FittedBox(fit: BoxFit.scaleDown, child: brand),
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      const Expanded(
                        child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: signature),
                      ),
                      Container(
                        width: 1,
                        height: 34,
                        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [palette.divider.withValues(alpha: 0), palette.outline, palette.divider.withValues(alpha: 0)],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          // Its own height only: the bottom bar's height is loose.
                          heightFactor: 1,
                          child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: brand),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Open-source licences", the last thing in the Settings list.
class SettingsLicencesLink extends StatelessWidget {
  const SettingsLicencesLink({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
    return Center(
      child: TextButton(
        key: const ValueKey('settings_licences'),
        style: TextButton.styleFrom(
          foregroundColor: palette.textSecondary,
          textStyle: type.caption.copyWith(decoration: TextDecoration.underline),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () => SettingsFooter.openLicences(context),
        child: const Text('Open-source licences'),
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
        const _CardHeading(icon: Icons.person_rounded, title: 'You', subtitle: 'Kept on this phone only.'),
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
        FilledButton(key: const ValueKey('user_name_save'), onPressed: _save, child: const Text('Save')),
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
          title: 'Theme',
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
        // Android only: just_audio has no equalizer on the iPhone.
        if (AudioEffects.supported) ...[
          const _CardDivider.betweenRows(),
          _NavRow(
            icon: Icons.equalizer_rounded,
            title: 'Equalizer',
            subtitle: ref.watch(equalizerProvider.select((e) => e.enabled))
                ? 'On · ${ref.watch(equalizerProvider.select((e) => e.preset))}'
                : 'Off. Presets, your own bands and a loudness boost.',
            onTap: () => showEqualizerSheet(context),
          ),
        ],
        const _CardDivider.betweenRows(),
        _SwitchRow(
          icon: Icons.lyrics_rounded,
          title: 'Find lyrics online',
          subtitle: 'When a song has no lyrics of its own, asks LRCLIB (lrclib.net) with its title, artist and length.',
          value: ref.watch(onlineLyricsProvider),
          onChanged: (v) => ref.read(onlineLyricsProvider.notifier).set(v),
        ),
      ],
    );
  }
}

/// Settings → Downloads (Android and iPhone: the phone can tell when data is
/// metered, through "mediahub/network").
class _DownloadsDataCard extends ConsumerWidget {
  const _DownloadsDataCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ask = ref.watch(askBeforeBigDownloadsProvider);
    return _SettingsCard(
      children: [
        const _CardHeading(
          icon: Icons.download_rounded,
          title: 'Downloads',
          subtitle: 'Where downloads go and how they use your data.',
        ),
        const _CardDivider.underHeading(),
        _SwitchRow(
          icon: Icons.signal_cellular_alt_rounded,
          title: 'Ask before big downloads on mobile data',
          subtitle: 'Asks first when a download over 100 MB would start on mobile data.',
          value: ask,
          onChanged: (v) => ref.read(askBeforeBigDownloadsProvider.notifier).set(v),
        ),
        const _CardDivider.betweenRows(),
        const _SaveLocationRow(),
      ],
    );
  }
}

/// Settings → Backup & restore: favourites, playlists, play history, video
/// positions and settings to a file the user picks, and back.
class _BackupCard extends ConsumerWidget {
  const _BackupCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SettingsCard(
      children: [
        const _CardHeading(
          icon: Icons.settings_backup_restore_rounded,
          title: 'Backup & restore',
          subtitle: 'Favourites, playlists, play history and settings. Not the songs and videos themselves.',
        ),
        const _CardDivider.underHeading(),
        if (ref.watch(backupFilePickerProvider).isSupported) ...[
          _NavRow(
            icon: Icons.save_alt_rounded,
            title: 'Save a backup',
            subtitle: 'Saves one small file wherever you choose.',
            onTap: () => saveLibraryBackup(context, ref),
          ),
          const _CardDivider.betweenRows(),
          _NavRow(
            icon: Icons.restore_rounded,
            title: 'Restore from backup',
            subtitle: 'Adds a backup to your library. Nothing is removed.',
            onTap: () => restoreLibraryBackup(context, ref),
          ),
        ] else
          const _InfoRow(icon: Icons.info_outline_rounded, title: 'Not on this device', body: backupIosMessage),
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
        const _CardHeading(icon: Icons.smart_display_rounded, title: 'Online', subtitle: 'YouTube in the Online tab.'),
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
          subtitle:
              'Personal use only. May break third-party service terms and is the user\'s own '
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
                                  child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Updating yt-dlp'),
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
            body:
                'MediaHub has no account of its own and syncs nothing. A YouTube sign-in '
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
        _InfoRow(icon: Icons.code_rounded, title: 'Crafted with precision by', body: CoreWatermark.fullName),
        if (kDebugMode) ...[
          const _CardDivider.betweenRows(),
          _NavRow(
            icon: Icons.bug_report_rounded,
            title: 'Diagnostics log',
            subtitle: 'Recent app events (playback, downloads, network), handy when something goes wrong.',
            onTap: () {
              context.push('/diagnostics');
            },
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Building blocks
// ---------------------------------------------------------------------------

/// What the phone allows for "Save to phone" (Android 10+, the iPhone).
final _phoneMediaCapsProvider = FutureProvider<PhoneMediaCapabilities>(
  (ref) => ref.watch(phoneMediaProvider).capabilities(),
);

/// Settings → Downloads → "Save downloads to".
class _SaveLocationRow extends ConsumerWidget {
  const _SaveLocationRow();

  static String _label(DownloadSaveLocation l) => switch (l) {
    DownloadSaveLocation.app => 'Inside MediaHub (private)',
    DownloadSaveLocation.phone => 'Phone storage',
  };

  static String _explain(DownloadSaveLocation l) => switch (l) {
    DownloadSaveLocation.app => 'Only MediaHub sees them.',
    DownloadSaveLocation.phone =>
      PlatformInfo.isIOS
          ? 'Songs in the Files app, videos also in Photos.'
          : 'Visible in Gallery, Files and other apps (Music/MediaHub, Movies/MediaHub).',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(downloadSaveLocationProvider);
    final supported = ref.watch(_phoneMediaCapsProvider).value?.canSaveToPhone ?? false;
    return _NavRow(
      key: const ValueKey('save_location_row'),
      icon: Icons.folder_rounded,
      title: 'Save downloads to',
      subtitle: supported
          ? '${_label(location)}. ${_explain(location)}'
          : 'Inside MediaHub. Phone storage needs Android 10 or newer.',
      onTap: supported ? () => _choose(context, ref, location) : null,
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref, DownloadSaveLocation current) async {
    final picked = await showChoiceDialog<DownloadSaveLocation>(
      context,
      title: 'Save downloads to',
      icon: Icons.folder_rounded,
      current: current,
      options: [
        for (final l in DownloadSaveLocation.values)
          ChoiceOption(
            l,
            _label(l),
            subtitle: _explain(l),
            icon: l == DownloadSaveLocation.app ? Icons.lock_outline_rounded : Icons.smartphone_rounded,
          ),
      ],
      footnote: 'Applies to new downloads. For one you already have, use "Save to phone" in its menu.',
    );
    if (picked != null) ref.read(downloadSaveLocationProvider.notifier).set(picked);
  }
}

/// Settings → App lock: fingerprint / face / the phone's PIN.
class _AppLockCard extends ConsumerWidget {
  const _AppLockCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    final notifier = ref.read(appLockProvider.notifier);
    final s = lock.settings;
    return _SettingsCard(
      children: [
        const _CardHeading(
          icon: Icons.lock_rounded,
          title: 'App lock',
          subtitle: 'Fingerprint, face or your phone PIN to open MediaHub. Music and its controls keep working.',
        ),
        const _CardDivider.underHeading(),
        _SwitchRow(
          icon: Icons.fingerprint_rounded,
          title: 'Lock MediaHub',
          subtitle: 'Asks when the app opens and after it was in the background.',
          value: s.enabled,
          onChanged: (v) async {
            final messenger = ScaffoldMessenger.maybeOf(context);
            final ok = await notifier.setEnabled(v);
            if (!ok && v) {
              messenger?.showSnackBar(
                const SnackBar(content: Text('Set a screen lock (PIN, pattern or fingerprint) on the phone first.')),
              );
            }
          },
        ),
        if (s.enabled) ...[
          const _CardDivider.betweenRows(),
          _NavRow(
            key: const ValueKey('app_lock_scope_row'),
            icon: Icons.shield_rounded,
            title: 'What it locks',
            subtitle: s.scope == AppLockScope.wholeApp
                ? AppLockSettings.scopeLabel(s.scope)
                : '${AppLockSettings.scopeLabel(s.scope)}. ${AppLockSettings.scopeHint(s.scope)}',
            onTap: () async {
              final picked = await _pick<AppLockScope>(
                context,
                'What it locks',
                AppLockScope.values,
                s.scope,
                AppLockSettings.scopeLabel,
              );
              if (picked != null) notifier.setScope(picked);
            },
          ),
          const _CardDivider.betweenRows(),
          _NavRow(
            key: const ValueKey('app_lock_after_row'),
            icon: Icons.timer_rounded,
            title: 'Lock again',
            subtitle: '${AppLockSettings.minutesLabel(s.lockAfterMinutes)} in the background',
            onTap: () async {
              final picked = await _pick<int>(
                context,
                'Lock again',
                AppLockSettings.minuteChoices,
                s.lockAfterMinutes,
                AppLockSettings.minutesLabel,
              );
              if (picked != null) notifier.setLockAfterMinutes(picked);
            },
          ),
        ],
      ],
    );
  }

  static Future<T?> _pick<T>(BuildContext context, String title, List<T> options, T current, String Function(T) label) {
    return showChoiceDialog<T>(
      context,
      title: title,
      icon: Icons.lock_rounded,
      current: current,
      options: [for (final o in options) ChoiceOption(o, label(o))],
    );
  }
}

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

  const _CardHeading({required this.icon, required this.title, required this.subtitle, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
    final color = accent ? palette.accent : palette.primary;
    // Its own node, so the next row is not read (and tapped) as part of it.
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.md12, AppSpacing.lg16, AppSpacing.sm8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _leadingSlot,
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 18, color: color),
              ),
            ),
            const SizedBox(width: AppSpacing.md12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(title, style: type.bodyStrong.copyWith(color: color)),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: type.caption),
                ],
              ),
            ),
          ],
        ),
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
      decoration: BoxDecoration(color: context.palette.primaryContainer, borderRadius: _tileRadius),
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

  /// Null: shown greyed out and not tappable (nothing to choose here).
  final VoidCallback? onTap;

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
    // Its own semantics node: without it a row can merge into the card and
    // be read (and tapped) as one node with the whole card's bounds.
    return Semantics(
      container: true,
      child: ListTile(
        minVerticalPadding: _rowVerticalPadding,
        visualDensity: _rowDensity,
        horizontalTitleGap: AppSpacing.md12,
        enabled: onTap != null,
        leading: _RowIcon(icon),
        title: Text(title, style: _rowTitleStyle(type)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(subtitle, style: _subtitleStyle(type)),
        ),
        trailing: onTap == null ? null : Icon(trailingIcon, color: palette.textMuted),
        onTap: onTap,
      ),
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
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.sm8, AppSpacing.lg16, AppSpacing.lg16),
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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg16),
      child: MergeSemantics(
        child: Row(
          children: [
            // The launch-screen logo, as in the footer.
            const MediaHubLogo(size: _leadingSlot),
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
                    children: [Text('Version $_appVersion', style: type.tabularFigures)],
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
                child: Text(text, style: type.metadata.copyWith(color: color)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
