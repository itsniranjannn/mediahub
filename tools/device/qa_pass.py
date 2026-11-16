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


def launch():
    dev.sh('am force-stop ' + PKG)
    dev.sh('monkey -p %s -c android.intent.category.LAUNCHER 1' % PKG)
    wait(6)


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
        if tap('^' + t + '$'):
            wait(1.2)
            shot('music_' + t.lower())
    tap('^Songs$')
    wait(1)


@step
def player():
    # play the first song row, then open Now Playing from the mini player
    tap('Audit Tone A4|Audit_Tone_A4', required=False) or tap('Tone', required=False)
    wait(2.5)
    shot('mini_player')
    tap('Now playing|Open player|mini player', required=False) or dev.sh('input tap 400 2020')
    wait(2)
    shot('now_playing')
    tap('Add to favou?rites|Favou?rite', required=False)
    wait(1.0)
    shot('now_playing_fav')
    wait(4.5)
    shot('now_playing_fav_after_snack')
    tap('Shuffle', required=False)
    wait(0.8)
    tap('Repeat', required=False)
    wait(0.8)
    shot('now_playing_shuffle_repeat')
    tap('Queue|Up next', required=False)
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
    tap('Mountain Sunrise', required=False)
    wait(4)
    shot('video_player')
    dev.sh('input tap 540 600')
    wait(0.8)
    shot('video_controls')
    tap('Rotate|Landscape|Full ?screen', required=False)
    wait(3)
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
    tap('Rotate|Portrait', required=False)
    wait(2.5)
    tap('Picture.in.picture|PiP', required=False)
    wait(3)
    shot('video_pip')
    dev.sh('monkey -p %s -c android.intent.category.LAUNCHER 1' % PKG)
    wait(3)
    key('BACK')
    wait(1.5)


@step
def explore():
    tap('Explore Tab', required=False)
    wait(2)
    shot('explore_empty')
    tap('Search YouTube|Search', required=False)
    wait(0.8)
    dev.sh("input text 'lofi%sbeats'")
    key('ENTER')
    wait(0.3)
    shot('explore_loading')
    wait(2)
    key('BACK')  # hide keyboard
    wait(1)
    shot('explore_results')
    swipe(540, 1800, 540, 800)
    wait(1)
    shot('explore_results_scrolled')


@step
def downloads():
    tap('Downloads Tab', required=False)
    wait(2)
    shot('downloads')
    tap('Add link|Paste link|New download|Download from link|Add', required=False)
    wait(1.5)
    shot('downloads_add_sheet')
    key('BACK')
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
