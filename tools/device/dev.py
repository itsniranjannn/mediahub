#!/usr/bin/env python
"""Tiny adb harness for driving the MediaHub test phone.  Usage: python dev.py <command> [args]

Env: AUDIT_SER = adb serial (default: the only connected device), AUDIT_PKG = app id
(default com.mediahub.app.audit, the side-by-side test build), SHOTS_DIR = screenshot folder
(default tools/device/shots, git-ignored).

Commands (device pixels are 1080x2400):
  state                      wake/keyguard/foreground/battery summary (exit 3 if the phone is locked/asleep)
  awake                      try to wake the screen; exit 3 if the keyguard is still showing
  fg                         current foreground package/activity
  shot NAME [--full]         screenshot -> <SHOTS_DIR>/NAME.png (half size 540x1200 unless --full). Prints the path.
  ui [REGEX] [--all]         dump the UI tree (Flutter semantics are exposed in the AUDIT build); lists nodes that have
                             text/content-desc or are clickable, with the tap centre in device px. REGEX filters.
  tapn REGEX [--nth N]       tap the centre of the Nth (default 1st, 0-based via --nth) node whose text/desc matches REGEX
  tap X Y                    tap device px
  taps X Y                   tap using coordinates read from a HALF-SIZE screenshot (doubles them)
  long X Y [MS]              long-press at device px
  swipe X1 Y1 X2 Y2 [MS]     swipe in device px
  key NAME                   adb input keyevent (e.g. BACK, HOME, ENTER, MEDIA_PLAY_PAUSE, MEDIA_NEXT, MEDIA_PREVIOUS)
  text "some text"           type text into the focused field (spaces handled)
  mark "label"               write a marker line into logcat (tag AUDIT)
  crashes [PKG]              recent FATAL/ANR lines for the package (default audit package)
  sh "cmd"                   adb shell <cmd>
"""
import io
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

ADB = os.path.expandvars(r'%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe')
SER = os.environ.get('AUDIT_SER', '')
PKG = os.environ.get('AUDIT_PKG', 'com.mediahub.app.audit')
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SHOTS = os.environ.get('SHOTS_DIR') or os.path.join(HERE, 'shots')
if os.name == 'nt' and re.match(r'^/[a-zA-Z]/', SHOTS):  # Git Bash path like /c/Users/... -> C:/Users/...
    SHOTS = SHOTS[1].upper() + ':' + SHOTS[2:]
os.makedirs(SHOTS, exist_ok=True)


def adb(*args, binary=False, timeout=90):
    target = ['-s', SER] if SER else []
    r = subprocess.run([ADB, *target, *args], capture_output=True, timeout=timeout)
    if binary:
        return r.stdout
    return (r.stdout.decode('utf-8', 'replace') + r.stderr.decode('utf-8', 'replace'))


def sh(cmd, timeout=90):
    return adb('shell', cmd, timeout=timeout)


def state():
    pw = sh('dumpsys power')
    wake = re.search(r'mWakefulness=(\w+)', pw)
    kg = 'isKeyguardShowing=true' in sh('dumpsys window')
    disp = re.search(r'Display State=(\w+)', sh('dumpsys display'))
    top = re.search(r'topResumedActivity=ActivityRecord\{[^ ]+ u\d+ ([^ ]+)', sh('dumpsys activity activities'))
    bat = re.search(r'level: (\d+)', sh('dumpsys battery'))
    return {
        'wakefulness': wake.group(1) if wake else '?',
        'display': disp.group(1) if disp else '?',
        'keyguard': kg,
        'top': top.group(1) if top else '?',
        'battery': bat.group(1) if bat else '?',
    }


def awake():
    st = state()
    if st['wakefulness'] != 'Awake' or st['display'] != 'ON':
        sh('input keyevent KEYCODE_WAKEUP')
        time.sleep(1.5)
        st = state()
    return st


def cmd_state():
    st = awake()
    print(st)
    if st['keyguard'] or st['wakefulness'] != 'Awake':
        print('PHONE LOCKED OR ASLEEP - ask the user to unlock it; do not try to enter a PIN.')
        sys.exit(3)


def cmd_shot(name, full=False):
    from PIL import Image
    data = adb('exec-out', 'screencap', '-p', binary=True)
    im = Image.open(io.BytesIO(data)).convert('RGB')
    if not full:
        im = im.resize((im.width // 2, im.height // 2))
    path = os.path.join(SHOTS, name + '.png')
    im.save(path)
    print(path + ('  (full 1080x2400)' if full else '  (HALF size 540x1200: multiply coordinates by 2 or use `taps`)'))


def dump_ui():
    # uiautomator waits for the UI to go idle, so it can hang while a video or animation runs;
    # a short timeout per try keeps a hang from blocking the whole run.
    last = ''
    for _ in range(3):
        try:
            out = sh('uiautomator dump /sdcard/_ui.xml', timeout=30)
        except subprocess.TimeoutExpired:
            sh('pkill -f uiautomator', timeout=10)
            last = 'timed out (screen never went idle)'
            continue
        if 'dumped' in out.lower():
            xml = adb('exec-out', 'cat', '/sdcard/_ui.xml', binary=True).decode('utf-8', 'replace')
            if xml.strip().startswith('<'):
                return xml
        last = out
        time.sleep(1.0)
    raise SystemExit('uiautomator dump failed: ' + last.strip()[:200])


BOUNDS = re.compile(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]')


def nodes(show_all=False):
    root = ET.fromstring(dump_ui())
    res = []
    for n in root.iter('node'):
        a = n.attrib
        text = a.get('text', '')
        desc = a.get('content-desc', '')
        clickable = a.get('clickable') == 'true' or a.get('long-clickable') == 'true' or a.get('checkable') == 'true'
        if not (text or desc or clickable or show_all):
            continue
        m = BOUNDS.match(a.get('bounds', ''))
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        res.append({
            'pkg': a.get('package', ''),
            'cls': a.get('class', '').split('.')[-1],
            'text': text,
            'desc': desc,
            'click': a.get('clickable') == 'true',
            'long': a.get('long-clickable') == 'true',
            'check': a.get('checkable') == 'true',
            'checked': a.get('checked') == 'true',
            'enabled': a.get('enabled') != 'false',
            'focused': a.get('focused') == 'true',
            'cx': (x1 + x2) // 2,
            'cy': (y1 + y2) // 2,
            'w': x2 - x1,
            'h': y2 - y1,
            'rid': a.get('resource-id', ''),
        })
    return res


def label(n):
    """Text and content-desc joined, without a leading space when one is empty (so ^...$ anchors work)."""
    return ' '.join(x for x in (n['text'], n['desc']) if x)


def fmt(i, n):
    flags = ''.join([
        ' click' if n['click'] else '',
        ' long' if n['long'] else '',
        ' checkable' if n['check'] else '',
        ' CHECKED' if n['checked'] else '',
        ' DISABLED' if not n['enabled'] else '',
        ' focused' if n['focused'] else '',
    ])
    label = n['text']
    if n['desc'] and n['desc'] != n['text']:
        label = (label + ' | ' if label else '') + n['desc']
    return '#%d [%s] "%s" c=(%d,%d) %dx%d%s %s' % (
        i, n['cls'], label.replace('\n', ' / ')[:140], n['cx'], n['cy'], n['w'], n['h'], flags, n['pkg'])


def cmd_ui(rx=None, show_all=False):
    ns = nodes(show_all)
    pat = re.compile(rx, re.I) if rx else None
    shown = 0
    for i, n in enumerate(ns):
        if pat and not pat.search(label(n) + ' ' + n['rid']):
            continue
        print(fmt(i, n))
        shown += 1
    print('-- %d node(s) shown of %d' % (shown, len(ns)))


def cmd_tapn(rx, nth=0):
    ns = nodes()
    pat = re.compile(rx, re.I)
    hits = [n for n in ns if pat.search(label(n))]
    if len(hits) <= nth:
        print('NO MATCH for /%s/ (nth=%d). Candidates on screen:' % (rx, nth))
        for i, n in enumerate(ns[:60]):
            print(fmt(i, n))
        sys.exit(2)
    n = hits[nth]
    sh('input tap %d %d' % (n['cx'], n['cy']))
    print('tapped ' + fmt(0, n))


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return
    c, rest = a[0], a[1:]
    if c == 'state':
        cmd_state()
    elif c == 'awake':
        st = awake()
        print(st)
        if st['keyguard']:
            sys.exit(3)
    elif c == 'fg':
        st = state()
        print(st['top'])
    elif c == 'shot':
        cmd_shot(rest[0], '--full' in rest)
    elif c == 'ui':
        flags = [x for x in rest if x.startswith('--')]
        pos = [x for x in rest if not x.startswith('--')]
        cmd_ui(pos[0] if pos else None, '--all' in flags)
    elif c == 'tapn':
        nth = 0
        if '--nth' in rest:
            i = rest.index('--nth')
            nth = int(rest[i + 1])
            rest = rest[:i] + rest[i + 2:]
        cmd_tapn(rest[0], nth)
    elif c == 'tap':
        sh('input tap %s %s' % (rest[0], rest[1]))
    elif c == 'taps':
        sh('input tap %d %d' % (int(rest[0]) * 2, int(rest[1]) * 2))
    elif c == 'long':
        ms = rest[2] if len(rest) > 2 else '900'
        sh('input swipe %s %s %s %s %s' % (rest[0], rest[1], rest[0], rest[1], ms))
    elif c == 'swipe':
        ms = rest[4] if len(rest) > 4 else '300'
        sh('input swipe %s %s %s %s %s' % (rest[0], rest[1], rest[2], rest[3], ms))
    elif c == 'key':
        k = rest[0].upper()
        if not k.startswith('KEYCODE_') and not k.isdigit():
            k = 'KEYCODE_' + k
        sh('input keyevent ' + k)
    elif c == 'text':
        s = rest[0].replace(' ', '%s').replace("'", "'\\''")
        sh("input text '%s'" % s)
    elif c == 'mark':
        sh("log -t AUDIT '%s'" % rest[0].replace("'", ''))
    elif c == 'crashes':
        pkg = rest[0] if rest else PKG
        out = sh('logcat -d -b crash')
        print('\n'.join(l for l in out.splitlines() if pkg in l or 'FATAL' in l)[-4000:] or 'no crash-buffer entries for ' + pkg)
        out = sh('logcat -d -b main -s ActivityManager:E AndroidRuntime:E')
        print('\n'.join(l for l in out.splitlines() if pkg in l or 'ANR' in l)[-2000:])
    elif c == 'sh':
        print(sh(rest[0]))
    else:
        print('unknown command: ' + c)
        print(__doc__)
        sys.exit(1)


if __name__ == '__main__':
    main()
