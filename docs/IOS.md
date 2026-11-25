# MediaHub on iPhone

Last updated: 2026-11-25. Branch: `chore/license-authorship`.

**Read this first.** The iPhone app has never been built or run, because building it needs a Mac.
Everything below comes from reading MediaHub's code and the plugins' own iPhone code, plus tests that
pretend to be an iPhone (`PlatformInfo.debugIsIOS = true`). A passing test run proves the logic, not
the iPhone. Section 6 is the checklist for the first build; section 7 is what to try on the iPhone.

## 1. At a glance

| | What it means |
|---|---|
| **Same** | Works the same way as on Android (same Dart code, the plugin does the same thing). |
| **Different** | Works, but not the same way, or with less. |
| **Missing** | Not there on iPhone. Some of it needs Swift code, some of it Apple does not allow. |

The short version: music, playlists, Liked songs, search, the basic video player, the Online tab and
direct-link and YouTube downloads are there. The things missing are mostly the ones that need native
iPhone code: picture-in-picture for your own videos, the volume raiser, the share sheet, and reading
songs and videos that are already on the iPhone.

## 2. The same on iPhone

- **Music**: play, pause, next, previous (fast repeated presses add up), shuffle that stays on, repeat
  off / all / one, the seek bar, speed 0.5x to 2x, the queue (play next, add, drag, swipe away), the
  sleep timer with its fade, the last queue back (paused) when you open the app.
- **Lock screen and Control Center**: title, artist, cover, play/pause, previous, next and a slider you
  can drag. Music keeps playing with the screen locked.
- **Library**: Liked songs, playlists, sorting, search (Devanagari and romanised Nepali, for example
  "resham"), the Home rows, deleting a download.
- **Video**: ±10 s buttons, double tap, the seek bar, the rotation modes, full screen, speed, picture
  size (fit, fill, stretch, original) and pinch, subtitles, lock, Up next, Continue watching, the screen
  staying on, and resuming where you stopped.
- **Online tab**: real YouTube inside the app, MediaHub's search sheet, Copy link, Save to Liked songs or
  a playlist, YouTube Music, and YouTube and your music taking turns.
- **Downloads**: direct https links to audio or video, the list with pause / resume / cancel / retry,
  safe file names, and every safety rule (https only, no home or private network addresses, the 2 GB
  limit, a check that the file really is media).
- **Design**: the Bijuli colours and fonts, dark and light following the phone.

## 3. Different on iPhone

**Music**
- Swiping MediaHub away in the app switcher stops the music (an iPhone rule).
- After the app is closed the lock screen offers nothing (no "media resumption" on iPhone).
- "Resume when headphones reconnect" only works while MediaHub is open: iPhone pauses apps in the
  background.
- The lock-screen buttons only start working after something played in MediaHub once since it was
  opened (how the audio_service plugin works on iPhone). Until then AirPods or the car may start
  another app.
- Calls, Siri and alarms: the music comes back by itself when the iPhone says it may (fixed today).

**Library**
- The library holds only what MediaHub downloaded. Nothing else on the iPhone is read: not the Music
  app, not the Files app, not the camera roll.
- Albums and artists come from what the download knows: YouTube downloads are grouped by channel, and
  direct-link files mostly land under "Unknown album".
- Covers come from the download's own picture or from inside the file (fixed today for MP3, M4A and
  FLAC).

**Video**
- Plays MP4, MOV and M4V. MKV, WebM and AVI do not play on iPhone; MediaHub now says so plainly.
- A call or Siri pauses the video; it comes back by itself when the iPhone says it may (fixed today).
- AirPlay to an Apple TV should work (iPhone only), never tried.

**Online tab**
- Background play works another way: when the screen goes off, the YouTube sound is handed to the
  iPhone's own player (current video only: no autoplay, Next or live streams). With Auto PiP on,
  WebKit's own picture-in-picture is tried first.
- The iPhone has no Back button; WebKit's edge swipe goes back inside the page.
- Signing in to YouTube: the same "Sign in to YouTube" menu row as Android. Google decides whether it
  allows it; never tried on an iPhone.

**Downloads**
- YouTube: only the files YouTube serves ready-made (usually 360p video with sound, or M4A audio). No
  1080p or 4K, and no MP3, because yt-dlp cannot run on iPhone.
- Downloads only carry on while MediaHub is open or playing sound. There is no download notification.
- Free space: iPhone does not tell the app, so no figure is shown; a full iPhone gets "Your iPhone is
  full" (fixed today).
- Downloads go into the iPhone's iCloud or computer backup (Android keeps them out of backups).
- Pasting a link copied in another app makes iPhone ask "Allow Paste" (an iPhone rule).

## 4. Missing on iPhone

| Missing | Why | What it needs |
|---|---|---|
| Like, shuffle and repeat on the lock screen | The plugin does not offer them on iPhone | A changed copy of audio_service (Swift), medium |
| Share a song, video or link; getting a file out of the app | No iPhone side for MediaHub's share channel | Swift share sheet or the share_plus plugin, small |
| Songs and videos already on the iPhone (Files, AirDrop, "Open in", Apple Music, Photos) | Nothing reads them | Files import: medium. Apple Music and Photos: medium to large |
| Volume and brightness swipes, the volume panel, the volume-key display | Android-only code | Swift, small (brightness, key display) to medium (system volume) |
| Volume raiser above 100% | The iPhone player stops at 100% | A changed copy of the video plugin, large |
| Picture-in-picture for your own videos | The iPhone video plugin has none | A changed copy of the video plugin, large |
| Instagram, TikTok, Facebook, X, Vimeo, SoundCloud, Dailymotion, Reddit links | yt-dlp cannot run on iPhone | Not possible the same way |
| YouTube above 720p | YouTube keeps picture and sound apart there | Joining them in Swift, medium to large |
| Downloads that keep going with the app closed | iPhone pauses the app | Swift background transfers, large |
| CarPlay browsing | Apple must grant the CarPlay audio entitlement to the developer account first (a request form, rarely given to a private app) | Not possible for MediaHub today |
| Equalizer and loudness boost | just_audio has no equalizer on iPhone (AVPlayer has no band EQ); the Now Playing and Settings rows are hidden | An AVAudioEngine player of our own, large |
| Deleting the iPhone's own songs and videos | MediaHub never sees them (no Music or Photos library access) | MediaHub deletes its own downloads only; that is the limit |

## 5. Fixed today (2026-11-19), iPhone side

All of these are in the code with tests that act as an iPhone. None has run on a real iPhone yet.

**Music and the lock screen**
- After a call, Siri or an alarm, the music plays again when the iPhone says it may. A video on
  screen does too. A press of play or pause in between keeps it as you left it.
- A song that cannot play (missing, moved or broken) no longer makes the player go silent: it moves on
  to the next song that works, says "Can't play ..." once, and stops if nothing in the queue plays
  (both phones).
- Screen-off YouTube: if Apple's player refuses the sound link, MediaHub tries once more with a fresh
  link, then asks the YouTube page to keep playing and puts your own queue back. Your repeat setting no
  longer makes the YouTube sound loop for ever.
- The app can no longer hang on the launch screen if the media controls are slow to start: it opens
  after 8 seconds at most.

**Downloads**
- Downloads are found again after an app update or reinstall (iPhone moves the app's folder each
  time; with a free Apple ID that happens every week).
- An old YouTube download link (they expire after a few hours) is looked up again, and the download
  carries on from where it stopped.
- No made-up "10 GB free"; a full iPhone gets a plain message.
- The link card no longer tells you to turn on a switch the iPhone does not have.
- WebM, MKV, Ogg, Opus and AVI links are refused up front, because the iPhone cannot play them.

**Library**
- Covers are read from inside downloaded MP3, M4A and FLAC files.
- Empty Songs, Videos, Albums and Artists tabs say "... you download in MediaHub show up here" with an
  "Open Downloads" button. The refresh buttons that could find nothing are gone, and so is the rescan
  when you come back to the app.
- Settings → Privacy talks about iPhone Settings.
- Search treats curly and straight quotes and dashes the same, and the search boxes (also the Online
  one) no longer autocorrect or swap in curly quotes (both phones).

**Online tab and video**
- Links that open a new window behave; outside links go to Safari.
- A harmless "load interrupted" error no longer shows the error screen.
- No signal, a call, roaming off and mobile data off for MediaHub count as offline; mobile data off
  says so.
- Share sheets and system pop-ups no longer hide the toolbar or turn the screen; only a real
  full-screen video does.
- Clear site data really clears everything on iPhone (and signs you out).
- Long-pressing a link no longer opens a preview, and an iPad gets the mobile site.
- On iOS 15 search still works.
- Video: a swipe that starts at the left edge seeks instead of closing the video. Files the iPhone
  cannot play get a plain message, no pointless "Try again", and are never marked missing.

**Project**
- The app id is now `com.mediahub.app` (`com.mediahub.app.RunnerTests` for the tests), the same as on
  Android. No team is set: you pick yours in Xcode (section 6).

## 5a. Added 2026-11-23, iPhone side

Swift lives in `ios/Runner/AppDelegate.swift` (no new Xcode files), registered in
`didInitializeImplicitFlutterEngine` next to the plugins. Dart tests pass; the Swift has not been compiled.

- **Backup & restore** (Settings): "Save a backup" writes the file to a temporary folder and opens the
  iPhone's "Save to Files" picker (`UIDocumentPickerViewController(forExporting:asCopy:)`). "Restore from
  backup" opens the Files picker for JSON files (`forOpeningContentTypes: [.json, .data]`), reads the
  picked file with security-scoped access (an iCloud Drive file is fetched first) and refuses one over the
  size limit (`TOO_LARGE`), exactly like Android's `mediahub/backup_files`. Backing out of either picker
  says nothing, as on Android.
- **"Ask before big downloads on mobile data"** (Settings → Downloads) now shows on iPhone. A new channel,
  `mediahub/network` `isMetered`, answers from `NWPathMonitor`: mobile data, an expensive network (a
  personal hotspot) or Low Data Mode count as metered. Android answers the same channel from
  `ConnectivityManager` (`NetworkChannel.kt`), so the question no longer needs the personal tools
  (yt-dlp) on either phone. No answer = no question.
- **Resume after other apps**: starting the watcher no longer throws on iPhone (there is no native side;
  the iPhone itself says when music may come back).
- **Choose quality**: audio rows say "M4A (AAC) · 128 kbps" on iPhone, and there are never MP3 rows.
- The launch image was already the app glyph (not Flutter's placeholder), so it was left as it is.

## 5b. Added 2026-11-25, iPhone side (written, never compiled)

Swift is again in `ios/Runner/AppDelegate.swift` (`PhoneMediaChannel`, `mediahub/phone_media`),
registered next to the backup and network channels. Dart tests act as an iPhone; nothing here has been
built.

- **Save downloads to: Phone storage** (Settings → Downloads) and **Save to phone** (a download's menu):
  - *Audio*: nothing moves. `Info.plist` now has `UIFileSharingEnabled` and
    `LSSupportsOpeningDocumentsInPlace`, so MediaHub's Documents folder (with `downloads/`) shows in the
    Files app under On My iPhone → MediaHub. "Save to phone" on a song says "Already in the Files app".
  - *Video*: a copy is added to Photos with `PHPhotoLibrary` (add-only access,
    `NSPhotoLibraryAddUsageDescription`). MediaHub keeps its own copy to play it and never reads Photos,
    so the library still shows it once. Formats Photos refuses (WebM, MKV) give `UNSUPPORTED`; a refused
    permission gives "Allow MediaHub to add to Photos in Settings".
  - **Risk to check on the first build**: with file sharing on, the Files app shows *everything* in
    Documents, also `settings.json`, the diagnostics log and the database (`media_hub_db.sqlite`).
    Deleting those in Files loses favourites and playlists. The fix is moving them to Library/Application
    Support with a one-time migration: done on 2026-11-25 (section 5c).
- **App lock**: `local_auth` (Face ID / Touch ID, the passcode as fallback). `Info.plist` has
  `NSFaceIDUsageDescription`. The lock screen covers the app or only the Downloads and Online tabs;
  music and the lock-screen controls keep working.
- **Delete from phone**: only MediaHub's own downloads (as before). The iPhone's own Music and Photos
  are never read, so they cannot be deleted from MediaHub; `deleteFromPhone` answers false.
- **Lyrics**: the same on both phones for downloads (a `.lrc` next to the file, ID3 `USLT`, MP4
  `©lyr`, FLAC `LYRICS`, and LRCLIB when turned on). No Swift.
- **Equalizer**: hidden (see section 4).
- **CarPlay**: not possible without Apple's entitlement (section 4). Android Auto has no iPhone part.

To try on the iPhone: Files app → On My iPhone → MediaHub → downloads shows the songs; "Save to phone" on
a video asks for Photos once and the video appears in Photos; App lock with Face ID and with the
passcode; lock, leave the app for the set minutes, come back (locked), music keeps playing meanwhile.

## 5c. Fixed 2026-11-25 (security audit), iPhone side (written, never compiled)

- **Private files out of the Files app.** `UIFileSharingEnabled` / `LSSupportsOpeningDocumentsInPlace`
  stay on, because they are how downloaded songs show in the Files app (Save to phone for audio). But
  Documents used to also hold `settings.json`, the database (`media_hub_db.sqlite` with `-wal`/`-shm`)
  and `diagnostics.log`. Anyone with the phone could open `settings.json` in Files, set
  `"app_lock_enabled": false` and walk past App lock, or delete the database.
  - They now live in **Library/Application Support**, which the Files app never shows
    (`lib/core/storage/app_private_dir.dart`, `appPrivateDataDir()`); Android keeps its private
    `app_flutter` folder, nothing moves there.
  - **One-time migration** at start, before anything opens them (`migratePrivateFilesOutOfDocuments()`
    in `main.dart`): each of those files is renamed from Documents into Application Support (copy + delete
    if a rename fails). If a file is already in Application Support, that copy wins and the Documents
    copy is deleted. A file that cannot move stays and is tried again next start.
  - **App lock reads its switch from Application Support only** (`SettingsStore` loads from
    `appPrivateDataDir()`); an edited `settings.json` left in Documents is ignored and removed.
  - What stays in Documents: `downloads/` (the user-visible music, with the downloads' covers and the
    yt-dlp work folder, which is unused on iPhone) and `MediaHub/` exports. Caches were already outside
    Documents: the media-session covers in `Library/Caches/np_art`, online lyrics in
    `Application Support/lyrics`, artwork in memory.
  - To check on the first build: Files → On My iPhone → MediaHub shows `downloads` only; settings,
    favourites and playlists survive the update from a build that had them in Documents.
- **App switcher snapshot.** While App lock is on, Dart sends `setSecure` on `mediahub/privacy_screen`
  (`PrivacyScreenChannel` in `AppDelegate.swift`). It covers the window with a plain view and a lock
  glyph when the scene resigns active (`UIScene.willDeactivateNotification`, the notification behind
  `sceneWillResignActive`) and removes it when the scene is active again, so the app switcher never
  shows a locked screen's content. `SceneDelegate` stays Flutter's own.
- **App lock timing** uses a monotonic `Stopwatch`, not the wall clock (changing the date cannot skip it),
  and turns itself off with a message when the phone no longer has a passcode.

## 6. First build on a Mac (checklist)

1. **A Mac with Xcode 16 or newer** (the video plugin needs it) and the command line tools:
   `xcode-select --install`. iOS 15 is the minimum the app supports.
2. **Flutter 3.47.x**, the same as on Windows (the iPhone start-up code uses an API from this version).
3. **CocoaPods**: `brew install cocoapods` (or `sudo gem install cocoapods`). It is needed even though
   the project also uses Swift Package Manager: `flutter_inappwebview_ios` (the Online tab) ships only a
   CocoaPods recipe.
4. `git clone https://github.com/itsniranjannn/mediahub.git`, then
   `flutter pub get`.
5. **Do not start with `cd ios && pod install`.** There is no `ios/Podfile` yet; Flutter writes it on
   the first build. Run `flutter build ios --release` (or, with the iPhone plugged in,
   `flutter run --release`) first. It creates the Podfile and runs CocoaPods itself.
6. **Internet during the first build.** Two native build steps run for the first time: the SQLite one
   downloads a ready-made library, and the `objective_c` one compiles code for the file-folder plugin
   with the Xcode tools. If either fails, the app opens empty (no database, no downloads folder).
7. **Signing**: open `ios/Runner.xcworkspace` in Xcode → Runner → Signing & Capabilities → pick your
   Team (and do the same for RunnerTests). The app id is `com.mediahub.app`.
   - A **free Apple ID** works for your own iPhone only: each install lasts 7 days, at most 3 apps, and
     the iPhone needs Developer Mode (Settings → Privacy & Security). Every reinstall moves the app's
     folder; the fix from today finds the downloads again.
   - **Family iPhones** need the paid Apple Developer Program, then TestFlight (or an ad hoc build).
8. **Use a real iPhone and a release (or profile) build.** A debug build will not start from the home
   screen, and the iPhone simulator on an Apple Silicon Mac may fail to build the Online tab's plugin
   (it allows only Intel simulators).
9. **Online tab with Block ads on** (the default): YouTube must load. With Block ads on, the iPhone
   first compiles a WebKit content rule list for ad addresses (`online_ad_block.dart`); if WebKit
   cannot compile it, the plugin only prints the error to the Xcode console and loads nothing, so the
   tab stays blank. If the tab is blank, turn Block ads off (Settings → Online): if YouTube then loads,
   the rule list is the cause.
10. Then go through section 7 on the iPhone.

## 7. What to try on the iPhone (first run)

- Open the app a few times from cold: it starts, the dark and light themes follow the phone.
- Online: browse, search, play a video; lock the screen and listen (Background play on, then off);
  do it once on mobile data too: the hand-off gives Apple's player 4 seconds per try, which may be
  too short there (if the sound stops, say so); picture-in-picture by button and by leaving the app;
  outside links open Safari; a link that opens a new window; Clear site data; on an iPad, the mobile
  site.
- Online: More options → Sign in to YouTube. Write down exactly what Google says if it refuses.
- Online with Block ads on: a video with an ad plays the ad silently and skips it as soon as YouTube
  offers Skip, then the video plays on with its sound; the lock screen shows the video, never the ad.
- Downloads: a YouTube video and its audio (Choose quality), a direct MP3 and MP4 link, a WebM link
  (it should be refused). Pause one, close the app for an hour, come back and resume it.
- Music: play a downloaded YouTube song; check its length, seeking and fast Next presses; the lock
  screen and Control Center (cover, slider, buttons); AirPods and car buttons after reopening the app.
- Calls: play music, have someone call you, hang up: the music should come back. Do the same with Siri
  and with a video on screen.
- Install a new build over the old one: songs and videos must still play and keep their covers.
- Video: ±10 s, double tap, swipe to seek near the left edge, rotation modes, an MKV file (plain message).
- Settings: Privacy wording, Clear YouTube data, Resume when headphones reconnect.
- Backup: Save a backup → save it to On My iPhone and to iCloud Drive; cancel once (nothing should be
  said). Restore from backup → pick that file (also once from iCloud Drive while it is not downloaded
  yet), then a big non-backup file (should say it is too large), then cancel. Try it on an iPad too (the
  picker is presented from the top screen).
- Mobile data: with Wi-Fi off, start a YouTube download over 100 MB: the question must appear. Then on
  Wi-Fi (no question), on a personal hotspot, and with Low Data Mode on (both should ask).
- Music with another app's audio: start and stop another app's sound while MediaHub waits to resume;
  nothing should crash or show an error.
- Choose quality on a YouTube link: the audio rows say "M4A (AAC) · ... kbps", no MP3.

## 8. Still needs Swift or a Mac (with sizes)

- **Small**: the share sheet; keeping downloads and the database out of iCloud backup (the database,
  settings and log left Documents on 2026-11-25, section 5c); a little extra background time for the screen-off YouTube hand-off and running
  downloads; video brightness; the volume-key display; covers and video thumbnails from the iPhone.
- **Medium**: importing your own files (Files app, AirDrop, "Open in"); the Like heart on the lock
  screen; setting the system volume from the swipe; YouTube above 720p.
- **Large**: picture-in-picture for your own videos; the volume raiser above 100%; downloads that carry
  on with the app closed; the Apple Music library and Photos videos; CarPlay.
- **Every row in this file** also needs one pass on a real iPhone.
