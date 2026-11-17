// Tests for assets/web/youtube_bridge.js (the Online tab's media bridge).
//
// Run from the repo root (Node 18+, no npm packages):
//   node --test "test/js/*_test.js"
// (Node 22+ no longer takes a bare folder there) or just this file:
//   node test/js/youtube_bridge_test.js
//
// The script runs in a vm context with tiny DOM stubs: a window, a document
// whose prototype has the real `hidden` / `visibilityState` getters, event
// dispatch with capture and bubble phases, one <video> and a few elements
// found by selector.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const SOURCE = fs.readFileSync(path.join(__dirname, '..', '..', 'assets', 'web', 'youtube_bridge.js'), 'utf8');
const TOKEN = '0123456789abcdef0123456789abcdef';

class ClassList {
  constructor() {
    this.set = new Set();
  }
  add(c) {
    this.set.add(c);
  }
  remove(c) {
    this.set.delete(c);
  }
  contains(c) {
    return this.set.has(c);
  }
}

class Target {
  constructor() {
    this.listeners = [];
  }
  addEventListener(type, fn, capture) {
    this.listeners.push({ type, fn, capture: capture === true || !!(capture && capture.capture) });
  }
  removeEventListener() {}
}

class Element extends Target {
  constructor(tag, parent) {
    super();
    this.tagName = tag.toUpperCase();
    this.classList = new ClassList();
    this.parentElement = parent || null;
    this.children = [];
    this.attributes = {};
    this.isConnected = true;
    this.clicks = 0;
  }
  setAttribute(k, v) {
    this.attributes[k] = v;
  }
  getAttribute(k) {
    return this.attributes[k] || null;
  }
  appendChild(child) {
    this.children.push(child);
    child.parentElement = this;
    return child;
  }
  click() {
    this.clicks++;
  }
  focus() {
    this.focused = true;
  }
}

class Event {
  constructor(type, target) {
    this.type = type;
    this.target = target;
    this.stopped = false;
  }
  stopImmediatePropagation() {
    this.stopped = true;
  }
  stopPropagation() {
    this.stopped = true;
  }
}

/** Builds a fresh page and runs the bridge in it. */
function makePage(opts = {}) {
  const env = { realHidden: false, posted: [], timers: [], backCalls: 0, now: 1000000 };

  class FakeDocument extends Target {}
  Object.defineProperty(FakeDocument.prototype, 'hidden', {
    configurable: true,
    get() {
      return env.realHidden;
    },
  });
  Object.defineProperty(FakeDocument.prototype, 'visibilityState', {
    configurable: true,
    get() {
      return env.realHidden ? 'hidden' : 'visible';
    },
  });

  const doc = new FakeDocument();
  const html = new Element('html');
  const head = new Element('head', html);
  const body = new Element('body', html);
  const player = new Element('div', body);
  const video = new Element('video', player);
  Object.assign(video, {
    paused: true,
    ended: false,
    currentTime: 0,
    duration: 213.5,
    playbackRate: 1,
    readyState: 4,
    muted: false,
    seeking: false,
    videoWidth: 1280,
    videoHeight: 720,
    playCalls: 0,
    pauseCalls: 0,
    play() {
      this.playCalls++;
      this.paused = false;
      return Promise.resolve();
    },
    pause() {
      this.pauseCalls++;
      this.paused = true;
    },
  });
  const nextButton = opts.nextButton ? new Element('button', body) : null;
  const all = [html, head, body, player, video].concat(nextButton ? [nextButton] : []);
  const selectors = {
    'video.html5-main-video': video,
  };
  if (nextButton) selectors['.ytp-next-button'] = nextButton;
  doc.documentElement = html;
  doc.head = head;
  doc.body = body;
  doc.title = opts.title || 'Never Gonna Give You Up - YouTube';
  doc.hasFocus = () => !env.realHidden;
  doc.querySelector = (sel) => {
    if (opts.throwingDom) throw new Error('DOM exploded');
    return selectors[sel] || null;
  };
  doc.querySelectorAll = (sel) => {
    if (opts.throwingDom) throw new Error('DOM exploded');
    const classes = sel.split(',').map((s) => s.trim().replace(/^\./, ''));
    return all.filter((el) => classes.some((c) => el.classList.contains(c)));
  };
  doc.createElement = (tag) => {
    const el = new Element(tag);
    all.push(el);
    return el;
  };

  const href = opts.href || 'https://m.youtube.com/watch?v=dQw4w9WgXcQ';
  const parsed = new URL(href);
  const win = new Target();
  Object.assign(win, {
    document: doc,
    Document: FakeDocument,
    navigator: {},
    location: { href, protocol: parsed.protocol, hostname: parsed.hostname },
    history: {
      length: opts.historyLength || 1,
      back() {
        env.backCalls++;
      },
    },
    setTimeout(fn) {
      env.timers.push(fn);
      return env.timers.length;
    },
  });
  win.window = win;
  win.top = opts.inIframe ? {} : win;
  if (opts.nativeMediaSession) {
    // A WebKit-like media session: a real accessor on the prototype.
    const native = { actions: {}, metadataSet: null };
    class MediaSession {
      setActionHandler(action, handler) {
        native.actions[action] = handler;
      }
    }
    Object.defineProperty(MediaSession.prototype, 'metadata', {
      configurable: true,
      get() {
        return native.metadataSet;
      },
      set(v) {
        native.metadataSet = v;
      },
    });
    win.navigator.mediaSession = new MediaSession();
    win.MediaMetadata = function (init) {
      Object.assign(this, init);
    };
    env.native = native;
  }
  if (!opts.bridgeLate) {
    win.flutter_inappwebview = {
      callHandler(name, msg) {
        env.posted.push({ name, msg });
        return Promise.resolve();
      },
    };
  }

  const context = vm.createContext(win);
  // Date.now inside the page follows env.now so the throttles are testable.
  vm.runInContext('Date.now = function () { return __now(); };', Object.assign(context, { __now: () => env.now }));
  vm.runInContext(SOURCE.split('__MEDIAHUB_BRIDGE_TOKEN__').join(TOKEN), context, { filename: 'youtube_bridge.js' });

  // Inside the vm the page's `window` is the context's global proxy, not `win`.
  const pageWindow = vm.runInContext('this', context);

  function dispatch(target, type, pathNodes, bubbles = true) {
    const ev = new Event(type, target === win ? pageWindow : target);
    const nodes = pathNodes || [win, doc, target];
    for (const node of nodes) {
      for (const l of node.listeners) {
        if (l.type === type && l.capture) {
          l.fn.call(node, ev);
          if (ev.stopped) return ev;
        }
      }
    }
    if (!bubbles) return ev;
    for (const node of [...nodes].reverse()) {
      for (const l of node.listeners) {
        if (l.type === type && !l.capture) {
          l.fn.call(node, ev);
          if (ev.stopped) return ev;
        }
      }
    }
    return ev;
  }

  function flushTimers() {
    const t = env.timers.splice(0);
    t.forEach((fn) => fn());
  }

  function media() {
    return env.posted.filter((p) => p.msg.k === 'media').map((p) => p.msg);
  }

  function command(name, arg) {
    return vm.runInContext(`window.__mediahubBridge.command(${JSON.stringify(name)}, ${JSON.stringify(arg)})`, context);
  }

  return { env, win, doc, html, head, video, player, body, nextButton, dispatch, flushTimers, media, command, context };
}

test('installs in the main frame only', () => {
  const top = makePage();
  assert.equal(typeof top.win.__mediahubBridge, 'object');
  const iframe = makePage({ inIframe: true });
  assert.equal(iframe.win.__mediahubBridge, undefined);
});

test('installs on https YouTube pages only, so no other page sees the token', () => {
  for (const href of [
    'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    'https://youtube.com/',
    'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
  ]) {
    const p = makePage({ href });
    assert.equal(typeof p.win.__mediahubBridge, 'object', href);
  }
  for (const href of [
    'https://evil.example/watch?v=dQw4w9WgXcQ',
    'https://youtube.com.evil.example/',
    'https://notyoutube.com/',
    'http://m.youtube.com/watch?v=dQw4w9WgXcQ',
    'https://accounts.google.com/',
  ]) {
    const p = makePage({ href });
    assert.equal(p.win.__mediahubBridge, undefined, href);
    assert.equal(p.env.posted.length, 0, href);
    p.video.play();
    p.dispatch(p.video, 'play');
    p.flushTimers();
    p.dispatch(p.win, 'flutterInAppWebViewPlatformReady', [p.win]);
    assert.equal(p.env.posted.length, 0, `${href} must not hear from the bridge`);
    assert.equal(p.doc.listeners.length, 0, `${href} gets no listeners`);
  }
});

test('says "ready" once per document', () => {
  const p = makePage();
  // The platform bridge was already up at document start, then the plugin
  // fires its platform-ready event when the page finishes loading.
  p.dispatch(p.win, 'flutterInAppWebViewPlatformReady', [p.win]);
  assert.equal(p.env.posted.filter((x) => x.msg.k === 'ready').length, 1);
});

test('the bridge object cannot be replaced by the page', () => {
  const p = makePage();
  vm.runInContext('try { window.__mediahubBridge = null; } catch (e) {}', p.context);
  assert.equal(typeof p.win.__mediahubBridge.command, 'function');
});

test('posts a ready message carrying the token and page URL', () => {
  const p = makePage();
  const ready = p.env.posted.find((x) => x.msg.k === 'ready');
  assert.ok(ready);
  assert.equal(ready.name, 'mediahubBridge');
  assert.equal(ready.msg.t, TOKEN);
  assert.equal(ready.msg.u, 'https://m.youtube.com/watch?v=dQw4w9WgXcQ');
});

test('background play: the page looks visible and never hears it was hidden', () => {
  const p = makePage();
  const heard = [];
  p.doc.addEventListener('visibilitychange', () => heard.push('doc'));
  p.win.addEventListener('pagehide', () => heard.push('pagehide'));
  p.env.realHidden = true;
  assert.equal(p.doc.hidden, false);
  assert.equal(p.doc.visibilityState, 'visible');
  assert.equal(p.doc.webkitHidden, false);
  assert.equal(p.doc.hasFocus(), true);
  p.dispatch(p.doc, 'visibilitychange', [p.win, p.doc]);
  p.dispatch(p.win, 'pagehide', [p.win]);
  assert.deepEqual(heard, []);
  assert.equal(p.win.__mediahubBridge.reallyHidden(), true);
});

test('background play off: the real visibility comes through, live', () => {
  const p = makePage();
  const heard = [];
  p.doc.addEventListener('visibilitychange', () => heard.push('doc'));
  assert.equal(p.command('setBackgroundPlay', false), true);
  p.env.realHidden = true;
  assert.equal(p.doc.hidden, true);
  assert.equal(p.doc.visibilityState, 'hidden');
  assert.equal(p.doc.hasFocus(), false);
  p.dispatch(p.doc, 'visibilitychange', [p.win, p.doc]);
  assert.deepEqual(heard, ['doc']);
  p.command('setBackgroundPlay', true);
  assert.equal(p.doc.hidden, false);
});

test('window blur is swallowed but an input losing focus is not', () => {
  const p = makePage();
  const heard = [];
  p.doc.addEventListener('blur', (e) => heard.push(e.target === p.win ? 'window' : 'input'), true);
  p.win.addEventListener('blur', () => heard.push('window-bubble'));
  const input = new Element('input', p.body);
  // blur does not bubble: only capture listeners and the target hear it.
  p.dispatch(input, 'blur', [p.win, p.doc, input], false);
  p.dispatch(p.win, 'blur', [p.win], false);
  assert.deepEqual(heard, ['input']);
});

test('media events post compact JSON with the token, status and position', () => {
  const p = makePage();
  p.env.posted.length = 0;
  p.video.currentTime = 12.3456;
  p.video.play();
  p.dispatch(p.video, 'play');
  const m = p.media();
  assert.equal(m.length, 1);
  assert.equal(m[0].t, TOKEN);
  assert.equal(m[0].s, 'playing');
  assert.equal(m[0].e, 'play');
  assert.equal(m[0].p, 12.346);
  assert.equal(m[0].d, 213.5);
  assert.equal(m[0].ti, 'Never Gonna Give You Up');
  assert.equal(m[0].vw, 1280);
  assert.equal(m[0].u, 'https://m.youtube.com/watch?v=dQw4w9WgXcQ');
  p.video.pause();
  p.dispatch(p.video, 'pause');
  assert.equal(p.media()[1].s, 'paused');
  p.video.ended = true;
  p.dispatch(p.video, 'ended');
  assert.equal(p.media()[2].s, 'ended');
});

test('timeupdate is throttled to about once a second', () => {
  const p = makePage();
  p.video.play();
  p.dispatch(p.video, 'play');
  p.env.posted.length = 0;
  p.dispatch(p.video, 'timeupdate');
  p.env.now += 250;
  p.dispatch(p.video, 'timeupdate');
  p.env.now += 250;
  p.dispatch(p.video, 'timeupdate');
  assert.equal(p.media().length, 1);
  p.env.now += 1000;
  p.dispatch(p.video, 'timeupdate');
  assert.equal(p.media().length, 2);
});

test('muted feed previews are ignored', () => {
  const p = makePage();
  p.env.posted.length = 0;
  const preview = new Element('video', p.body);
  Object.assign(preview, { muted: true, paused: false, ended: false, currentTime: 1, duration: 30, readyState: 4 });
  p.dispatch(preview, 'play');
  p.dispatch(preview, 'timeupdate');
  assert.equal(p.media().length, 0);
});

test('media session polyfill captures metadata and handlers', () => {
  const p = makePage();
  vm.runInContext(
    `navigator.mediaSession.metadata = new MediaMetadata({ title: 'Song', artist: 'Channel',
       artwork: [{ src: 'https://i.ytimg.com/vi/x/default.jpg', sizes: '120x90' },
                 { src: 'https://i.ytimg.com/vi/x/hqdefault.jpg', sizes: '480x360' }] });
     navigator.mediaSession.setActionHandler('nexttrack', function () { window.nextCalls = (window.nextCalls || 0) + 1; });`,
    p.context
  );
  p.flushTimers();
  const last = p.media().pop();
  assert.equal(last.ti, 'Song');
  assert.equal(last.ar, 'Channel');
  assert.equal(last.aw, 'https://i.ytimg.com/vi/x/hqdefault.jpg');
  assert.equal(last.n, true);
  assert.equal(p.command('next'), true);
  assert.equal(p.win.nextCalls, 1);
});

test('play, pause and seekTo drive the main video', () => {
  const p = makePage();
  assert.equal(p.command('play'), true);
  assert.equal(p.video.playCalls, 1);
  assert.equal(p.command('pause'), true);
  assert.equal(p.video.pauseCalls, 1);
  assert.equal(p.command('seekTo', 42.5), true);
  assert.equal(p.video.currentTime, 42.5);
  assert.equal(p.command('seekTo', 99999), true);
  assert.equal(p.video.currentTime, 213.5, 'clamped to the duration');
  assert.equal(p.command('seekTo', 'x'), false);
});

test('next falls back to the next button when the page has no handler', () => {
  const p = makePage({ nextButton: true });
  assert.equal(p.command('next'), true);
  assert.equal(p.nextButton.clicks, 1);
  const none = makePage();
  assert.equal(none.command('next'), false);
});

test('previous restarts past 3 s, else the handler, else history back', () => {
  const p = makePage({ historyLength: 3 });
  p.video.currentTime = 10;
  assert.equal(p.command('previous'), true);
  assert.equal(p.video.currentTime, 0);
  assert.equal(p.env.backCalls, 0);
  // Under 3 s, no handler: back in history.
  p.video.currentTime = 1;
  assert.equal(p.command('previous'), true);
  assert.equal(p.env.backCalls, 1);
  // With a previoustrack handler it wins.
  vm.runInContext(
    "navigator.mediaSession.setActionHandler('previoustrack', function () { window.prevCalls = (window.prevCalls || 0) + 1; });",
    p.context
  );
  assert.equal(p.command('previous'), true);
  assert.equal(p.win.prevCalls, 1);
  assert.equal(p.env.backCalls, 1);
});

test('wraps a native media session and de-duplicates the same press', () => {
  const p = makePage({ nativeMediaSession: true });
  vm.runInContext(
    "navigator.mediaSession.setActionHandler('nexttrack', function () { window.nextCalls = (window.nextCalls || 0) + 1; });",
    p.context
  );
  const nativeHandler = p.env.native.actions.nexttrack;
  assert.equal(typeof nativeHandler, 'function', 'still registered with the browser');
  // The lock screen presses next (browser calls the handler), then the same
  // press arrives from Dart's notification path: one skip only.
  nativeHandler({ action: 'nexttrack' });
  assert.equal(p.win.nextCalls, 1);
  assert.equal(p.command('next'), true);
  assert.equal(p.win.nextCalls, 1);
  // Later presses go through again.
  p.env.now += 2000;
  p.command('next');
  assert.equal(p.win.nextCalls, 2);
  // And the other order: Dart first, browser right after.
  p.env.now += 2000;
  p.command('next');
  nativeHandler({ action: 'nexttrack' });
  assert.equal(p.win.nextCalls, 3);
  // Metadata still reaches the browser.
  vm.runInContext("navigator.mediaSession.metadata = new MediaMetadata({ title: 'T' });", p.context);
  assert.equal(p.env.native.metadataSet.title, 'T');
});

test('picture-in-picture layout class makes the playing video fill the window', () => {
  const p = makePage();
  p.video.play();
  p.dispatch(p.video, 'play');
  assert.equal(p.command('setPipLayout', true), true);
  assert.ok(p.html.classList.contains('mediahub-pip'));
  assert.ok(p.video.classList.contains('mediahub-pip-video'));
  assert.ok(p.player.classList.contains('mediahub-pip-ancestor'));
  const style = p.head.children.find((c) => c.tagName === 'STYLE');
  assert.ok(style && /position:fixed!important/.test(style.textContent));
  assert.ok(/object-fit:contain!important/.test(style.textContent));
  assert.ok(/z-index:2147483647!important/.test(style.textContent));
  p.command('setPipLayout', false);
  assert.ok(!p.html.classList.contains('mediahub-pip'));
  assert.ok(!p.video.classList.contains('mediahub-pip-video'));
  assert.ok(!p.player.classList.contains('mediahub-pip-ancestor'));
});

test('iOS picture-in-picture uses webkitSetPresentationMode', () => {
  const p = makePage();
  let mode = null;
  p.video.webkitSupportsPresentationMode = (m) => m === 'picture-in-picture';
  p.video.webkitSetPresentationMode = (m) => {
    mode = m;
  };
  assert.equal(p.command('enterPip'), true);
  assert.equal(mode, 'picture-in-picture');
  p.video.autoPictureInPicture = false;
  p.command('setAutoPip', true);
  assert.equal(p.video.autoPictureInPicture, true);
});

test('messages wait for the platform bridge, then flush', () => {
  const p = makePage({ bridgeLate: true });
  p.video.play();
  p.dispatch(p.video, 'play');
  assert.equal(p.env.posted.length, 0);
  p.win.flutter_inappwebview = {
    callHandler(name, msg) {
      p.env.posted.push({ name, msg });
      return Promise.resolve();
    },
  };
  p.dispatch(p.win, 'flutterInAppWebViewPlatformReady', [p.win]);
  assert.deepEqual(
    p.env.posted.map((x) => x.msg.k),
    ['ready', 'media']
  );
});

test('never throws into the page, even when the DOM does', () => {
  const p = makePage({ throwingDom: true });
  assert.equal(p.command('play'), false);
  assert.equal(p.command('next'), false);
  assert.equal(p.command('setPipLayout', true), true);
  assert.equal(p.command('focusSearch'), false);
  assert.equal(p.command('noSuchCommand'), false);
  assert.equal(p.command('constructor'), false);
  assert.doesNotThrow(() => p.dispatch(p.video, 'play'));
});

test('the token placeholder is the only templated part', () => {
  assert.equal(SOURCE.split('__MEDIAHUB_BRIDGE_TOKEN__').length, 2, 'exactly one placeholder');
});
