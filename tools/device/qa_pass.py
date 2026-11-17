#!/usr/bin/env python
"""Visual QA pass on the emulator: install, grant, launch, visit every screen, screenshot.

Usage: python qa_pass.py <round-name> [--install APK] [--only step,step]
Screenshots land in <SHOTS_DIR>/<round>/NN_<step>.png (half size); see dev.py for env vars.
Steps print the semantics nodes they found so missing labels show up too.
"""
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dev  # noqa: E402

ROUND = sys.argv[1] if len(sys.argv) > 1 else 'r1'
OUT = os.path.join(dev.SHOTS, ROUND)
os.makedirs(OUT, exist_ok=True)
PKG = dev.PKG
n = [0]


def shot(name):
    n[0] += 1
    fname = '%02d_%s' % (n[0], name)
    data = dev.adb('exec-out', 'screencap', '-p', binary=True)
    path = os.path.join(OUT, fname + '.png')
    try:
        from PIL import Image
        import io
        im = Image.open(io.BytesIO(data))
        im = im.resize((im.width // 2, im.height // 2))
        im.save(path)
    except Exception:
        open(path, 'wb').write(data)
    print('SHOT', path)
    return path


def wait(s=1.2):
    time.sleep(s)


def tap(rx, nth=0, required=False):
    try:
        dev.cmd_tapn(rx, nth)
        return True
    except SystemExit:
        if required:
            raise
        print('  (no node for %r)' % rx)
        return False
    except Exception as e:  # noqa: BLE001
        print('  tap failed %r: %s' % (rx, e))
        return False


def key(k):
    dev.sh('input keyevent KEYCODE_' + k)


def swipe(x1, y1, x2, y2, ms=300):
    dev.sh('input swipe %d %d %d %d %d' % (x1, y1, x2, y2, ms))


def nodes(rx=None):
    try:
        dev.cmd_ui(rx)
    except Exception as e:  # noqa: BLE001
        print('  ui dump failed', e)


def install(apk):
    print(subprocess.run([dev.ADB, *(['-s', dev.SER] if dev.SER else []), 'install', '-r', '-d', apk], capture_output=True, text=True).stdout[-400:])
    for p in ['READ_MEDIA_AUDIO', 'READ_MEDIA_VIDEO', 'POST_NOTIFICATIONS']:
        dev.sh('pm grant %s android.permission.%s' % (PKG, p))


def wait_for(rx, timeout=30):
    """Poll the UI tree until a node matches rx (the emulator can be slow right after boot)."""
    import re
    pat = re.compile(rx, re.I)
    end = time.time() + timeout
    while time.time() < end:
        try:
            if any(pat.search(dev.label(x)) for x in dev.nodes()):
                return True
        except BaseException:  # noqa: BLE001  (dump can fail while the app is busy)
            pass
        time.sleep(1.5)
    print('  (timed out waiting for %r)' % rx)
    return False


def dismiss_system_tips():
    """Close Android's own one-time tips (e.g. "Viewing full screen ... Got it") that steal focus."""
    try:
        for x in dev.nodes():
            if x['pkg'] == 'android' and x['text'] in ('Got it', 'GOT IT', 'OK'):
                dev.sh('input tap %d %d' % (x['cx'], x['cy']))
                print('  dismissed system tip')
                time.sleep(1)
                return
    except BaseException:  # noqa: BLE001
        pass


def tap_field(nth=0):
    """Tap the nth text field of the app (EditText nodes have no label when empty)."""
    try:
        fields = [x for x in dev.nodes() if x['cls'] == 'EditText' and x['pkg'] == PKG]
        if len(fields) > nth:
            dev.sh('input tap %d %d' % (fields[nth]['cx'], fields[nth]['cy']))
            return True
    except BaseException:  # noqa: BLE001
        pass
    print('  (no text field)')
    return False


def hide_keyboard():
    """BACK only while the keyboard is up, otherwise BACK would leave the screen."""
    if 'mInputShown=true' in dev.sh('dumpsys input_method'):
        key('BACK')
        wait(0.8)


def launch():
    dev.sh('am force-stop ' + PKG)
    dev.sh('monkey -p %s -c android.intent.category.LAUNCHER 1' % PKG)
    wait_for('Home Tab', 40)
    wait(1.5)


STEPS = {}


def step(fn):
    STEPS[fn.__name__] = fn
    return fn


@step
def home():
    launch()
    shot('home')
    swipe(540, 1800, 540, 700)
    wait()
    shot('home_scrolled')
    swipe(540, 700, 540, 1900)
    wait(0.6)


@step
def music():
    tap('Music Tab', required=False)
    wait(2)
    shot('music_songs')
    nodes('Albums|Artists|Playlists|Folders|Songs')
    for t in ['Albums', 'Artists', 'Playlists']:
        if tap('^ ?' + t + '( / Tab|$)'):
            wait(1.2)
            shot('music_' + t.lower())
    tap('^ ?Songs( / Tab|$)')
    wait(1)


@step
def player():
    # play the first song row, then open Now Playing from the mini player
    # labels: song rows are "Song: <title> by <artist>"; the mini player is "Mini player: <title>"
    tap('Song: Audit.Tone.A4', required=False) or tap('Song: ', required=False)
    wait(2.5)
    shot('mini_player')
    tap('Mini player', required=False) or dev.sh('input tap 400 2070')
    wait(2)
    shot('now_playing')
    nodes('favou?rite')
    # anchored so the big Now Playing body node (whose label also mentions favourites) is skipped
    tap('(^| )(Add to|Remove from) favou?rites$', required=False)
    wait(1.0)
    shot('now_playing_fav')
    wait(4.5)
    shot('now_playing_fav_after_snack')
    tap('(^| )Shuffle (enabled|disabled|on|off)', required=False)
    wait(0.8)
    tap('(^| )Repeat mode', required=False)
    wait(0.8)
    shot('now_playing_shuffle_repeat')
    tap('View Queue|Up next', required=False)
    wait(1.5)
    shot('queue')
    key('BACK')
    wait(1)
    key('BACK')
    wait(1)


@step
def videos():
    tap('Videos Tab', required=False)
    wait(2.5)
    shot('videos')
    tap('Timelapse|Mountain Sunrise|Family Trip|Street Food', required=False)
    wait(4)
    shot('video_player')
    dev.sh('input tap 540 600')
    wait(0.8)
    shot('video_controls')
    tap('Rotate|Landscape|Full ?screen', required=False)
    wait(3)
    dismiss_system_tips()
    shot('video_landscape')
    # right side vertical swipe = volume, left = brightness, horizontal = seek
    swipe(1900, 700, 1900, 300, 500)
    wait(0.3)
    shot('video_volume_hud')
    wait(1)
    swipe(300, 300, 300, 700, 500)
    wait(0.3)
    shot('video_brightness_hud')
    wait(1)
    swipe(900, 540, 1500, 540, 600)
    wait(0.3)
    shot('video_seek_hud')
    wait(1)
    dismiss_system_tips()
    dev.sh('input tap 1200 540')  # show the controls again
    wait(0.8)
    tap('Rotate|Portrait', required=False)
    wait(2.5)
    dismiss_system_tips()
    dev.sh('input tap 540 600')
    wait(0.8)
    tap('Picture.in.picture|PiP', required=False)
    wait(3)
    shot('video_pip')
    dev.sh('monkey -p %s -c android.intent.category.LAUNCHER 1' % PKG)
    wait(3)
    key('BACK')
    wait(1.5)


def media_session():
    """Our app's entry in `dumpsys media_session`: (state, title) or (None, None)."""
    import re
    out = dev.sh('dumpsys media_session')
    # One block per session, from our "package=" line to the next session's.
    i = out.find('package=' + PKG)
    if i < 0:
        return (None, None)
    j = out.find('package=', i + 8)
    block = out[i:j if j > 0 else i + 4000]
    # "state=PlaybackState {state=3, ..." (older) or "{state=PLAYING(3), ..." (newer): keep the number.
    st = re.search(r'state=PlaybackState \{state=[A-Z_]*\(?(\d+)', block)
    title = re.search(r'description=([^,\r\n]+)', block)
    return (st.group(1) if st else None, title.group(1).strip() if title else None)


def wait_media(pred, timeout=8):
    end = time.time() + timeout
    last = (None, None)
    while time.time() < end:
        last = media_session()
        if pred(*last):
            return last
        time.sleep(0.8)
    return last


@step
def online():
    """Online tab on the emulator build (MEDIAHUB_ONLINE_FIXTURE=true): the fixture page plays a
    generated tone, so the bridge, the media notification, media keys, the mini player and
    picture-in-picture can be checked without reaching YouTube."""
    dismiss_system_tips()
    tap('Online Tab', required=False)
    wait(4)
    shot('online_fixture')
    nodes('Download|Copy link|Picture-in-picture|Background play|Auto PiP|Search YouTube')
    st, title = wait_media(lambda s, t: s is not None and t is not None and 'Tone' in t)
    print('  media session:', st, title)
    if not title or 'Tone' not in title:
        print('  (no YouTube entry in the media session; is this the fixture build?)')
    # The notification shade ("media dropdown").
    dev.sh('cmd statusbar expand-notifications')
    wait(1.5)
    shot('online_notification')
    dev.sh('cmd statusbar collapse')
    wait(0.8)
    # Media keys go through the notification's session to the page.
    key('MEDIA_PAUSE')
    print('  after MEDIA_PAUSE:', wait_media(lambda s, t: s == '2'))
    key('MEDIA_PLAY')
    print('  after MEDIA_PLAY:', wait_media(lambda s, t: s == '3'))
    key('MEDIA_NEXT')
    print('  after MEDIA_NEXT:', wait_media(lambda s, t: t is not None and 'Two' in t))
    wait(1)
    key('MEDIA_PREVIOUS')  # under 3 s: back to the previous track
    print('  after MEDIA_PREVIOUS:', wait_media(lambda s, t: t is not None and 'One' in t))
    # Mini player on another tab shows the video with a YOUTUBE tag.
    tap('Home Tab', required=False)
    wait(1.5)
    nodes('Mini player')
    shot('online_mini_player_on_home')
    tap('Mini player: YouTube', required=False)
    wait(2)
    # Picture-in-picture from the watch strip, then back.
    tap('^Picture-in-picture', required=False)
    wait(3)
    shot('online_pip')
    print('  pinned:', 'pinned' in dev.sh('dumpsys activity activities').lower())
    dev.sh('monkey -p %s -c android.intent.category.LAUNCHER 1' % PKG)
    wait(3)
    shot('online_after_pip')
    # Auto PiP: leaving the app while the video plays (Android 12+ enters by itself).
    key('HOME')
    wait(3)
    shot('online_auto_pip')
    print('  media session after HOME (background play):', media_session())
    dev.sh('monkey -p %s -c android.intent.category.LAUNCHER 1' % PKG)
    wait(3)
    key('MEDIA_PAUSE')
    wait(1)


@step
def downloads():
    tap('Downloads Tab', required=False)
    wait(2)
    shot('downloads')
    # the link field sits at the top of the screen (no separate add sheet)
    tap_field()
    wait(0.8)
    dev.sh("input text 'https://example.com/clip.mp4'")
    wait(0.8)
    shot('downloads_link_typed')
    hide_keyboard()
    wait(1)


@step
def settings():
    tap('Home Tab', required=False)
    wait(1.5)
    tap('^Settings$', required=False)
    wait(2)
    shot('settings')
    swipe(540, 1900, 540, 600)
    wait(1)
    shot('settings_scrolled')
    swipe(540, 1900, 540, 600)
    wait(1)
    shot('settings_bottom')
    key('BACK')
    wait(1)


def main():
    args = sys.argv[2:]
    if '--install' in args:
        install(args[args.index('--install') + 1])
    only = None
    if '--only' in args:
        only = args[args.index('--only') + 1].split(',')
    dev.awake()
    for name, fn in STEPS.items():
        if only and name not in only:
            continue
        print('== step', name)
        try:
            fn()
        except Exception as e:  # noqa: BLE001
            print('  step failed:', e)
    print(dev.sh('logcat -d -b crash')[-1500:] or 'no crashes')


if __name__ == '__main__':
    main()
