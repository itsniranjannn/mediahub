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
  const env = {
    realHidden: false,
    posted: [],
    timers: [],
    intervals: [],
    backCalls: 0,
    now: 1000000,
    observers: [],
    fetched: [],
    beacons: [],
    xhrSent: [],
  };

  // MutationObserver: a test says when the watched thing changed.
  class MutationObserver {
    constructor(callback) {
      this.callback = callback;
      this.target = null;
      env.observers.push(this);
    }
    observe(target, options) {
      this.target = target;
      this.options = options;
    }
    disconnect() {
      this.target = null;
    }
  }

  // The browser's own Response: json() and text() parse with the real JSON.
  class Response {
    constructor(body, url) {
      this.body = body;
      this.url = url;
    }
    json() {
      return Promise.resolve(JSON.parse(this.body));
    }
    text() {
      return Promise.resolve(this.body);
    }
  }

  class XMLHttpRequest extends Target {
    constructor() {
      super();
      this.events = [];
    }
    open(method, url) {
      this.url = url;
    }
    send() {
      env.xhrSent.push(this.url);
    }
    dispatchEvent(ev) {
      this.events.push(ev.type);
      return true;
    }
  }
  Object.defineProperty(XMLHttpRequest.prototype, 'readyState', {
    configurable: true,
    get() {
      return 1;
    },
  });

  // The page's own media element class: play() / pause() live on its
  // prototype, as in a browser, so the bridge can tell the page's script
  // calls apart from its own.
  class HTMLMediaElement extends Element {
    play() {
      this.playCalls++;
      this.paused = false;
      return Promise.resolve();
    }
    pause() {
      this.pauseCalls++;
      this.paused = true;
    }
  }

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
  const video = new HTMLMediaElement('video', player);
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
  });
  const nextButton = opts.nextButton ? new Element('button', body) : null;
  const all = [html, head, body, player, video].concat(nextButton ? [nextButton] : []);
  const selectors = {
    'video.html5-main-video': video,
  };
  if (nextButton) selectors['.ytp-next-button'] = nextButton;
  // At document start the page may have no <html> element yet.
  doc.documentElement = opts.noDocumentElement ? null : html;
  doc.head = opts.noDocumentElement ? null : head;
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
    HTMLMediaElement,
    MutationObserver,
    Response,
    XMLHttpRequest,
    Event,
    fetch(input) {
      env.fetched.push(typeof input === 'string' ? input : input.url);
      return Promise.resolve('answer');
    },
    navigator: {
      sendBeacon(url) {
        env.beacons.push(url);
        return true;
      },
    },
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
    setInterval(fn, ms) {
      env.intervals.push({ fn, ms });
      return env.intervals.length;
    },
  });
  win.window = win;
  win.top = opts.inIframe ? {} : win;
  // The phone's screen and the real outer window (shrinks in picture-in-picture).
  if (opts.screen) win.screen = { width: opts.screen[0], height: opts.screen[1] };
  if (opts.outer) {
    env.outer = { width: opts.outer[0], height: opts.outer[1] };
    Object.defineProperty(win, 'outerWidth', { configurable: true, enumerable: true, get: () => env.outer.width });
    Object.defineProperty(win, 'outerHeight', { configurable: true, enumerable: true, get: () => env.outer.height });
  }
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
  // Dart fills in the token and Settings → Online → Block ads ('on' / 'off').
  let source = SOURCE.split('__MEDIAHUB_BRIDGE_TOKEN__').join(TOKEN);
  if (!opts.rawBlockAds) source = source.split('__MEDIAHUB_BLOCK_ADS__').join(opts.blockAds === false ? 'off' : 'on');
  vm.runInContext(source, context, { filename: 'youtube_bridge.js' });

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

  /** Every interval of [ms] fires once (one minute of page time passes). */
  function tickIntervals(ms) {
    env.now += ms;
    env.intervals.filter((i) => i.ms === ms).forEach((i) => i.fn());
  }

  /** The observers watching [target] hear that it changed. */
  function mutated(target) {
    env.observers.filter((o) => o.target === target).forEach((o) => o.callback([]));
  }

  /** The parser made the <html> element (it had none at document start). */
  function attachDocumentElement() {
    doc.documentElement = html;
    doc.head = head;
    mutated(doc);
  }

  return {
    env,
    mutated,
    attachDocumentElement,
    win,
    doc,
    html,
    head,
    video,
    player,
    body,
    nextButton,
    selectors,
    dispatch,
    flushTimers,
    tickIntervals,
    media,
    command,
    context,
  };
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
    // Google's sign-in pages load in the tab, but never get the bridge.
    'https://accounts.google.com/v3/signin/identifier?continue=https%3A%2F%2Fwww.youtube.com%2Fsignin',
    'https://accounts.youtube.com/accounts/SetSID?ssdc=1',
    'https://ACCOUNTS.youtube.com/accounts/SetSID',
    'https://gds.google.com/web/recoveryoptions',
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

test('previous restarts past 3 s, else the page handler, else restarts: never history back', () => {
  const p = makePage({ historyLength: 3 });
  p.video.currentTime = 10;
  assert.equal(p.command('previous'), true);
  assert.equal(p.video.currentTime, 0);
  assert.equal(p.env.backCalls, 0);
  // Under 3 s, no handler: the video restarts; the browsing history is
  // never walked (the lock screen used to take the user back a page).
  p.video.currentTime = 1;
  assert.equal(p.command('previous'), true);
  assert.equal(p.video.currentTime, 0);
  assert.equal(p.env.backCalls, 0);
  // Pressed many times in a row: still never history.
  for (let i = 0; i < 10; i++) p.command('previous');
  assert.equal(p.env.backCalls, 0);
  // With a previoustrack handler it wins.
  p.video.currentTime = 1;
  vm.runInContext(
    "navigator.mediaSession.setActionHandler('previoustrack', function () { window.prevCalls = (window.prevCalls || 0) + 1; });",
    p.context
  );
  assert.equal(p.command('previous'), true);
  assert.equal(p.win.prevCalls, 1);
  assert.equal(p.env.backCalls, 0);
  // No video at all: nothing to do.
  const none = makePage({ historyLength: 3 });
  none.selectors['video.html5-main-video'] = null;
  assert.equal(none.command('previous'), false);
  assert.equal(none.env.backCalls, 0);
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

test('YouTube never sees the window as smaller than the screen (its picture-in-picture check)', () => {
  // A phone: 412 x 915 screen, the app's WebView 412 x 665.
  const p = makePage({ screen: [412, 915], outer: [412, 665] });
  const outer = () => Array.from(vm.runInContext('[window.outerWidth, window.outerHeight]', p.context));
  assert.deepEqual(outer(), [412, 915]);
  // Android picture-in-picture shrinks the whole window to about 204 x 151:
  // YouTube compares that with the screen and would pause the video.
  p.env.outer = { width: 204, height: 151 };
  assert.deepEqual(outer(), [412, 915]);
  // A real window larger than the screen keeps its own size.
  p.env.outer = { width: 1200, height: 2000 };
  assert.deepEqual(outer(), [1200, 2000]);
});

test('picture-in-picture shows only the video: YouTube\'s bars and banners are hidden', () => {
  const p = makePage();
  p.video.play();
  p.dispatch(p.video, 'play');
  p.command('setPipLayout', true);
  const style = p.head.children.find((c) => c.tagName === 'STYLE');
  assert.ok(/html\.mediahub-pip \*\{visibility:hidden!important\}/.test(style.textContent));
  assert.ok(/html\.mediahub-pip video\.mediahub-pip-video\{visibility:visible!important\}/.test(style.textContent));
  // Captions the viewer turned on are part of the video and stay.
  assert.ok(/html\.mediahub-pip \.ytp-caption-window-container \*\{visibility:visible!important\}/.test(style.textContent));
});

test('no screen or outer size: nothing breaks', () => {
  const p = makePage();
  assert.equal(vm.runInContext('window.outerWidth', p.context), 0);
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
  assert.equal(p.command('focusSearch'), false, 'gone: the search goes through our own sheet');
  assert.equal(p.command('search', 'lofi'), false);
  assert.equal(p.command('exitFullscreen'), false);
  assert.equal(p.command('noSuchCommand'), false);
  assert.equal(p.command('constructor'), false);
  assert.doesNotThrow(() => p.dispatch(p.video, 'play'));
});

test('two templated parts: the token and the Block ads switch, once each', () => {
  assert.equal(SOURCE.split('__MEDIAHUB_BRIDGE_TOKEN__').length, 2, 'exactly one token placeholder');
  assert.equal(SOURCE.split('__MEDIAHUB_BLOCK_ADS__').length, 2, 'exactly one Block ads placeholder');
  assert.ok(SOURCE.includes("var BLOCK_ADS = '__MEDIAHUB_BLOCK_ADS__' !== 'off';"));
});

// --- keep-alive and who paused the video (ONL-2) ---------------------------

function playing(p) {
  p.video.play();
  p.dispatch(p.video, 'play');
}

function pauseMsg(p) {
  return p.media().filter((m) => m.e === 'pause').pop();
}

test('keep-alive: YouTube\'s last-activity clock is refreshed every minute while Background play is on', () => {
  const p = makePage();
  assert.equal(p.env.intervals.length, 1);
  assert.equal(p.env.intervals[0].ms, 60000);
  vm.runInContext('window._lact = 1;', p.context);
  p.tickIntervals(60000);
  assert.equal(p.win._lact, p.env.now);
  p.tickIntervals(60000);
  assert.equal(p.win._lact, p.env.now, 'every minute, not once');
  p.command('setBackgroundPlay', false);
  const before = p.win._lact;
  p.tickIntervals(60000);
  assert.equal(p.win._lact, before, 'off: YouTube sees the real idle time');
});

test('a pause the page makes by itself is reported as such', () => {
  const p = makePage();
  playing(p);
  p.env.now += 60000;
  // YouTube's own script pauses the video, with no touch from the user.
  p.video.pause();
  p.dispatch(p.video, 'pause');
  const m = pauseMsg(p);
  assert.equal(m.s, 'paused');
  assert.equal(m.yp, true);
  assert.equal(m.na, false);
});

test('a pause right after the user touched the page is the user\'s', () => {
  const p = makePage();
  playing(p);
  p.env.now += 60000;
  p.dispatch(p.doc, 'pointerdown', [p.win, p.doc]);
  p.env.now += 300;
  p.video.pause(); // the page's pause button handler
  p.dispatch(p.video, 'pause');
  assert.equal(pauseMsg(p).yp, false);
  // A key press counts too.
  const q = makePage();
  playing(q);
  q.env.now += 60000;
  q.dispatch(q.doc, 'keydown', [q.win, q.doc]);
  q.video.pause();
  q.dispatch(q.video, 'pause');
  assert.equal(pauseMsg(q).yp, false);
});

test('a muted preview the page paused does not make the main video pause the page one', () => {
  const p = makePage();
  playing(p);
  p.env.now += 60000;
  const preview = new p.win.HTMLMediaElement('video', p.body);
  Object.assign(preview, { muted: true, paused: false, playCalls: 0, pauseCalls: 0 });
  preview.pause(); // the feed scrolls a preview away
  p.video.paused = true; // then the browser pauses the main video (audio focus)
  p.dispatch(p.video, 'pause');
  assert.equal(pauseMsg(p).yp, false);
});

test('a synthetic click from a script is not the user', () => {
  const p = makePage();
  playing(p);
  p.env.now += 60000;
  const ev = { type: 'pointerdown', isTrusted: false };
  p.doc.listeners.filter((l) => l.type === 'pointerdown').forEach((l) => l.fn(ev));
  p.video.pause();
  p.dispatch(p.video, 'pause');
  assert.equal(pauseMsg(p).yp, true);
});

test('our own pause command is never taken for the page\'s', () => {
  const p = makePage();
  playing(p);
  p.env.now += 60000;
  assert.equal(p.command('pause'), true);
  p.dispatch(p.video, 'pause');
  assert.equal(pauseMsg(p).yp, false);
  assert.equal(p.video.paused, true);
});

test('a pause by the browser itself (audio focus, a call) is not the page\'s', () => {
  const p = makePage();
  playing(p);
  p.env.now += 60000;
  p.video.paused = true; // no script call: the browser paused the element
  p.dispatch(p.video, 'pause');
  assert.equal(pauseMsg(p).yp, false);
  assert.equal(pauseMsg(p).na, false);
});

test('a pause from the phone\'s lock screen is flagged as the system controls', () => {
  const p = makePage({ nativeMediaSession: true });
  vm.runInContext(
    "navigator.mediaSession.setActionHandler('pause', function () { document.querySelector('video.html5-main-video').pause(); });",
    p.context
  );
  playing(p);
  p.env.now += 60000;
  p.env.native.actions.pause({ action: 'pause' }); // the browser runs the page's handler
  p.dispatch(p.video, 'pause');
  const m = pauseMsg(p);
  assert.equal(m.na, true);
  assert.equal(m.yp, false);
});

function stillWatchingButton(p) {
  const b = new Element('button', p.body);
  p.selectors['yt-confirm-dialog-renderer #confirm-button button'] = b;
  return b;
}

test('"Continue watching?" is confirmed after the page paused itself, and the video plays on', () => {
  const p = makePage();
  playing(p);
  p.env.now += 3600000;
  p.video.pause();
  p.dispatch(p.video, 'pause');
  const button = stillWatchingButton(p);
  const plays = p.video.playCalls;
  p.flushTimers();
  assert.equal(button.clicks, 1);
  assert.equal(p.video.paused, false);
  assert.equal(p.video.playCalls, plays + 1);
  // Once: a later minute does not click again.
  p.tickIntervals(60000);
  assert.equal(button.clicks, 1);
});

test('the keep-alive tick also confirms a prompt that showed up late', () => {
  const p = makePage();
  playing(p);
  p.env.now += 3600000;
  p.video.pause();
  p.dispatch(p.video, 'pause');
  p.flushTimers(); // no dialog yet
  const button = stillWatchingButton(p);
  p.tickIntervals(60000);
  assert.equal(button.clicks, 1);
});

test('a dialog is never confirmed after the user paused, touched the page since, or with Background play off', () => {
  // The user paused (touch just before): their dialog, their answer.
  const a = makePage();
  playing(a);
  a.env.now += 60000;
  a.dispatch(a.doc, 'touchstart', [a.win, a.doc]);
  a.video.pause();
  a.dispatch(a.video, 'pause');
  const ba = stillWatchingButton(a);
  a.flushTimers();
  a.tickIntervals(60000);
  assert.equal(ba.clicks, 0);

  // The page paused itself, then the user touched the page (opened a dialog).
  const b = makePage();
  playing(b);
  b.env.now += 60000;
  b.video.pause();
  b.dispatch(b.video, 'pause');
  b.env.now += 2000;
  b.dispatch(b.doc, 'pointerdown', [b.win, b.doc]);
  const bb = stillWatchingButton(b);
  b.flushTimers();
  b.tickIntervals(60000);
  assert.equal(bb.clicks, 0);

  // Background play off.
  const c = makePage();
  c.command('setBackgroundPlay', false);
  playing(c);
  c.env.now += 60000;
  c.video.pause();
  c.dispatch(c.video, 'pause');
  const bc = stillWatchingButton(c);
  c.flushTimers();
  assert.equal(bc.clicks, 0);

  // The video plays: nothing to confirm.
  const d = makePage();
  playing(d);
  const bd = stillWatchingButton(d);
  d.tickIntervals(60000);
  assert.equal(bd.clicks, 0);
});

// --- fullscreen, picture-in-picture, search (ONL-3, ONL-7, ONL-11) ---------

test('exitFullscreen leaves the page\'s fullscreen, or iOS\'s native video fullscreen', () => {
  const p = makePage();
  assert.equal(p.command('exitFullscreen'), false, 'nothing is fullscreen');
  let exits = 0;
  p.doc.fullscreenElement = p.video;
  p.doc.exitFullscreen = () => {
    exits++;
    p.doc.fullscreenElement = null;
    return Promise.resolve();
  };
  assert.equal(p.command('exitFullscreen'), true);
  assert.equal(exits, 1);

  const ios = makePage();
  let nativeExits = 0;
  ios.video.webkitDisplayingFullscreen = true;
  ios.video.webkitExitFullscreen = () => nativeExits++;
  assert.equal(ios.command('exitFullscreen'), true);
  assert.equal(nativeExits, 1);
});

test('exitPip returns from iOS picture-in-picture to the page', () => {
  const p = makePage();
  let mode = 'picture-in-picture';
  p.video.webkitPresentationMode = mode;
  p.video.webkitSetPresentationMode = (m) => {
    mode = m;
    p.video.webkitPresentationMode = m;
  };
  assert.equal(p.command('exitPip'), true);
  assert.equal(mode, 'inline');
  assert.equal(p.command('exitPip'), false, 'already inline');
});

test('search submits the query inside the page, by structure, never by label', () => {
  const p = makePage();
  const form = new Element('form', p.body);
  form.submits = 0;
  form.requestSubmit = () => form.submits++;
  const input = new Element('input', form);
  input.form = form;
  p.selectors['input[name="search_query"]'] = input;
  assert.equal(p.command('search', '  lofi   beats '), true);
  assert.equal(input.value, 'lofi beats');
  assert.equal(form.submits, 1);
  assert.equal(p.command('search', ''), false);
  assert.equal(p.command('search', 'x'.repeat(201)), false);
  assert.equal(p.command('search', 42), false);
  // No search field on this page: Dart loads the results page itself.
  const none = makePage();
  assert.equal(none.command('search', 'lofi'), false);
  // Search looks for no label in one language.
  const searchFn = SOURCE.slice(SOURCE.indexOf('function search('), SOURCE.indexOf('function exitPip('));
  assert.ok(searchFn.length > 100);
  assert.ok(!/aria-label/.test(searchFn), 'no aria-label selectors');
});

// --- iOS parity: search without requestSubmit, fullscreen reports ----------

function searchPage({ requestSubmit, button }) {
  const p = makePage();
  const form = new Element('form', p.body);
  form.submits = 0;
  if (requestSubmit) form.requestSubmit = () => form.submits++;
  const controls = [];
  if (button) {
    // A plain <button> in a form is a submit button (its type defaults to
    // "submit"); its click submits the form, so the page's handler runs.
    const b = new Element('button', form);
    b.type = button;
    b.click = () => {
      b.clicks++;
      if (b.type === 'submit') form.submits++;
    };
    controls.push(b);
  }
  form.querySelectorAll = () => controls;
  const input = new Element('input', form);
  input.form = form;
  const keys = [];
  input.dispatchEvent = (ev) => keys.push(ev.type);
  p.selectors['input[name="search_query"]'] = input;
  vm.runInContext(
    'window.KeyboardEvent = function (type) { this.type = type; }; window.Event = function (type) { this.type = type; };',
    p.context
  );
  return { p, form, input, keys, button: controls[0] };
}

test('search without requestSubmit (iOS 15) clicks the form\'s submit button, never a fake Enter', () => {
  const { p, form, input, keys, button } = searchPage({ requestSubmit: false, button: 'submit' });
  assert.equal(p.command('search', 'lofi beats'), true);
  assert.equal(input.value, 'lofi beats');
  assert.equal(button.clicks, 1);
  assert.equal(form.submits, 1, 'the form was really submitted');
  assert.ok(!keys.includes('keydown'), 'no scripted Enter key');
});

test('search without requestSubmit or a submit button says so, so Dart loads the results page', () => {
  for (const button of [null, 'button']) {
    const { p, form, keys } = searchPage({ requestSubmit: false, button });
    assert.equal(p.command('search', 'lofi'), false, `button: ${button}`);
    assert.equal(form.submits, 0);
    assert.ok(!keys.includes('keydown'), 'a scripted Enter does not submit a form: not tried');
  }
});

test('search with requestSubmit is unchanged: the form is submitted, no button click', () => {
  const { p, form, button } = searchPage({ requestSubmit: true, button: 'submit' });
  assert.equal(p.command('search', 'lofi'), true);
  assert.equal(form.submits, 1);
  assert.equal(button.clicks, 0);
});

function fullscreenReports(p) {
  return p.env.posted.filter((x) => x.msg.k === 'fs').map((x) => x.msg);
}

test('fullscreen: iOS native video fullscreen is reported on and off, with the token and page', () => {
  const p = makePage();
  p.video.webkitDisplayingFullscreen = true;
  p.dispatch(p.video, 'webkitbeginfullscreen', [p.win, p.doc, p.video], false);
  // The flag can lag behind the end event.
  p.dispatch(p.video, 'webkitendfullscreen', [p.win, p.doc, p.video], false);
  const fs = fullscreenReports(p);
  assert.deepEqual(fs.map((m) => m.on), [true, false]);
  assert.equal(fs[0].t, TOKEN);
  assert.equal(fs[0].u, 'https://m.youtube.com/watch?v=dQw4w9WgXcQ');
});

test('fullscreen: the player element going fullscreen counts; one report per change', () => {
  const p = makePage();
  p.doc.fullscreenElement = p.player; // YouTube puts the player box fullscreen, not the <video>
  p.dispatch(p.player, 'fullscreenchange', [p.win, p.doc, p.player]);
  p.dispatch(p.player, 'webkitfullscreenchange', [p.win, p.doc, p.player]);
  p.doc.fullscreenElement = null;
  p.dispatch(p.player, 'fullscreenchange', [p.win, p.doc, p.player]);
  assert.deepEqual(fullscreenReports(p).map((m) => m.on), [true, false]);
});

test('fullscreen: an element with no video in it is not a fullscreen video', () => {
  const p = makePage();
  const banner = new Element('div', p.body);
  p.doc.webkitFullscreenElement = banner;
  p.dispatch(banner, 'webkitfullscreenchange', [p.win, p.doc, banner]);
  assert.deepEqual(fullscreenReports(p), []);
});

test('fullscreen: the presentation mode "fullscreen" counts, picture-in-picture does not', () => {
  const p = makePage();
  p.video.webkitPresentationMode = 'fullscreen';
  p.dispatch(p.video, 'webkitpresentationmodechanged', [p.win, p.doc, p.video], false);
  p.video.webkitPresentationMode = 'picture-in-picture';
  p.dispatch(p.video, 'webkitpresentationmodechanged', [p.win, p.doc, p.video], false);
  assert.deepEqual(fullscreenReports(p).map((m) => m.on), [true, false]);
  const pip = p.env.posted.filter((x) => x.msg.k === 'pip').map((x) => x.msg.on);
  assert.deepEqual(pip, [false, true], 'the picture-in-picture reports stay as they were');
});

// --- the platform bridge is captured once (ONL-13) -------------------------

test('messages go through the platform bridge captured at injection, never a later wrapper', () => {
  const p = makePage();
  p.env.posted.length = 0;
  vm.runInContext(
    `window.stolen = [];
     var original = window.flutter_inappwebview.callHandler;
     window.flutter_inappwebview.callHandler = function (name, msg) {
       window.stolen.push(msg);
       return original.apply(this, arguments);
     };`,
    p.context
  );
  playing(p);
  assert.equal(p.media().length, 1, 'the real bridge still hears it');
  assert.equal(p.win.stolen.length, 0, 'the wrapper never sees a message or the token');
  // Swapping the whole object does not help either.
  vm.runInContext(
    "window.flutter_inappwebview = { callHandler: function (n, m) { window.stolen.push(m); } };",
    p.context
  );
  p.video.pause();
  p.dispatch(p.video, 'pause');
  assert.equal(p.media().length, 2);
  assert.equal(p.win.stolen.length, 0);
});

test('a platform bridge that arrives late is captured when it says it is ready', () => {
  const p = makePage({ bridgeLate: true });
  p.win.flutter_inappwebview = {
    callHandler(name, msg) {
      p.env.posted.push({ name, msg });
      return Promise.resolve();
    },
  };
  p.dispatch(p.win, 'flutterInAppWebViewPlatformReady', [p.win]);
  assert.deepEqual(p.env.posted.map((x) => x.msg.k), ['ready']);
  const stolen = [];
  p.win.flutter_inappwebview.callHandler = (n, m) => stolen.push(m);
  playing(p);
  assert.equal(p.media().length, 1);
  assert.deepEqual(stolen, []);
});

// --- Block ads (Settings → Online → Block ads) -------------------------------

const VIDEO_ID = 'dQw4w9WgXcQ';

/** A player API answer like YouTube's, with or without its ad fields. */
function playerJson({ ads = true, lengthSeconds = '213', videoId = VIDEO_ID, title = 'Never Gonna Give You Up' } = {}) {
  const o = {
    responseContext: { serviceTrackingParams: [{ service: 'GFEEDBACK' }] },
    playabilityStatus: { status: 'OK', playableInEmbed: true },
    streamingData: {
      expiresInSeconds: '21540',
      adaptiveFormats: [{ itag: 251, mimeType: 'audio/webm; codecs="opus"', url: 'https://rr1---sn-a.googlevideo.com/videoplayback?id=1' }],
    },
    videoDetails: { videoId, title, lengthSeconds, author: 'Rick Astley' },
    captions: { playerCaptionsTracklistRenderer: { captionTracks: [] } },
  };
  if (ads) {
    o.adPlacements = [{ adPlacementRenderer: { config: { adPlacementConfig: { kind: 'AD_PLACEMENT_KIND_START' } } } }];
    o.playerAds = [{ playerLegacyDesktopWatchAdsRenderer: { playerAdParams: {} } }];
    o.adSlots = [{ adSlotRenderer: { adSlotMetadata: { slotType: 'SLOT_TYPE_PLAYER_BYTES' } } }];
  }
  return o;
}

/** JSON.parse as the page calls it (the page's own JSON). */
function parseInPage(p, textValue, reviver) {
  p.context.__text = textValue;
  p.context.__reviver = reviver;
  return vm.runInContext('JSON.parse(__text, __reviver)', p.context);
}

function adStats(p) {
  return Object.assign({}, p.win.__mediahubBridge.adStats());
}

function adsStyle(p) {
  return p.html.children.filter((c) => c.tagName === 'STYLE' && c.attributes['data-mediahub'] === 'ads');
}

test('Block ads: the player data loses its ad fields and nothing else (JSON.parse)', () => {
  const p = makePage();
  const got = parseInPage(p, JSON.stringify(playerJson()));
  assert.equal(JSON.stringify(got), JSON.stringify(playerJson({ ads: false })));
  // No ads: exactly what the browser itself parses.
  const plain = JSON.stringify(playerJson({ ads: false }));
  assert.equal(JSON.stringify(parseInPage(p, plain)), plain);
  // A watch answer (a short list of parts) and a playerResponse inside another answer.
  const watch = [{ page: 'watch' }, { playerResponse: playerJson(), response: { contents: { a: 1 } } }];
  assert.equal(
    JSON.stringify(parseInPage(p, JSON.stringify(watch))),
    JSON.stringify([{ page: 'watch' }, { playerResponse: playerJson({ ads: false }), response: { contents: { a: 1 } } }])
  );
  // Other JSON that happens to use the same words is never touched.
  const other = JSON.stringify({ adSlots: 3, settings: { playerAds: true }, adPlacements: 'x' });
  assert.equal(JSON.stringify(parseInPage(p, other)), other);
  assert.equal(parseInPage(p, '42'), 42);
  assert.equal(parseInPage(p, 'null'), null);
  assert.equal(parseInPage(p, '"adSlots"'), 'adSlots');
  // A reviver still runs, and bad JSON still throws the browser's own error at the page.
  assert.equal(parseInPage(p, '{"a":1}', (k, v) => (k === 'a' ? v + 1 : v)).a, 2);
  assert.throws(() => parseInPage(p, '{oops'), (e) => e.name === 'SyntaxError');
  // The page still sees a native JSON.parse.
  assert.match(vm.runInContext('Function.prototype.toString.call(JSON.parse)', p.context), /\[native code\]/);
  assert.equal(adStats(p).pruned, 6);
});

test('Block ads: YouTube\'s "Ad blockers are not allowed" message is pruned, other messages stay', () => {
  const p = makePage();
  const data = playerJson({ ads: false });
  data.auxiliaryUi = {
    messageRenderers: {
      enforcementMessageViewModel: { title: "Ad blockers violate YouTube's Terms of Service" },
      bkaEnforcementMessageViewModel: { title: 'Ad blockers are not allowed on YouTube' },
      upsellDialogRenderer: { keep: true },
    },
  };
  const top = parseInPage(p, JSON.stringify(data));
  assert.equal(JSON.stringify(top.auxiliaryUi.messageRenderers), JSON.stringify({ upsellDialogRenderer: { keep: true } }));
  const nested = parseInPage(p, JSON.stringify({ playerResponse: data }));
  assert.equal(
    JSON.stringify(nested.playerResponse.auxiliaryUi.messageRenderers),
    JSON.stringify({ upsellDialogRenderer: { keep: true } })
  );
});

test('Block ads: the player and next answers lose the same fields, read as JSON or as text', async () => {
  const p = makePage();
  const R = p.win.Response;
  const body = JSON.stringify(playerJson());
  const player = 'https://m.youtube.com/youtubei/v1/player?prettyPrint=false';
  const fromJson = await new R(body, player).json();
  assert.equal(JSON.stringify(fromJson), JSON.stringify(playerJson({ ads: false })));
  const next = await new R(
    JSON.stringify({ responseContext: {}, playerResponse: playerJson(), contents: { b: 2 } }),
    'https://www.youtube.com/youtubei/v1/next'
  ).json();
  assert.equal(JSON.stringify(next.playerResponse), JSON.stringify(playerJson({ ads: false })));
  assert.equal(JSON.stringify(next.contents), '{"b":2}');
  assert.equal(await new R(body, player).text(), JSON.stringify(playerJson({ ads: false })));
  // Nothing to remove: the text is exactly as it came (spacing and all).
  const clean = JSON.stringify(playerJson({ ads: false }), null, 1);
  assert.equal(await new R(clean, player).text(), clean);
  // YouTube's anti-hijacking prefix stays in front.
  assert.equal(await new R(")]}'\n" + body, player).text(), ")]}'\n" + JSON.stringify(playerJson({ ads: false })));
  // Text that only looks like it: passed on as it is.
  assert.equal(await new R('"adSlots" is not JSON', player).text(), '"adSlots" is not JSON');
  // Other addresses are never touched.
  const browse = 'https://m.youtube.com/youtubei/v1/browse?prettyPrint=false';
  assert.ok(Array.isArray((await new R(body, browse).json()).adPlacements));
  assert.equal(await new R(body, browse).text(), body);
});

test("Block ads: the page's own ytInitialPlayerResponse and ytInitialData lose their ad fields", () => {
  const p = makePage();
  vm.runInContext(`window.ytInitialPlayerResponse = ${JSON.stringify(playerJson())};`, p.context);
  const got = vm.runInContext('window.ytInitialPlayerResponse', p.context);
  assert.equal(JSON.stringify(got), JSON.stringify(playerJson({ ads: false })));
  assert.equal(vm.runInContext('window.ytInitialPlayerResponse === ytInitialPlayerResponse', p.context), true);
  vm.runInContext('window.ytInitialData = { responseContext: {}, contents: { c: 3 }, adSlots: [1] };', p.context);
  assert.equal(JSON.stringify(vm.runInContext('window.ytInitialData', p.context)), '{"responseContext":{},"contents":{"c":3}}');
  // Set again by the page (or cleared): still the page's value.
  vm.runInContext('window.ytInitialPlayerResponse = null;', p.context);
  assert.equal(vm.runInContext('window.ytInitialPlayerResponse', p.context), null);
  // A string (parsed later with JSON.parse, which prunes it then) is kept as it is.
  vm.runInContext('window.ytInitialData = \'{"adSlots":1}\';', p.context);
  assert.equal(vm.runInContext('window.ytInitialData', p.context), '{"adSlots":1}');
});

/** The player data of a video reaches the page (a player API answer it parses). */
function seePlayerData(p, json = {}) {
  parseInPage(p, JSON.stringify(playerJson(json)));
}

// YouTube gives each stream its own address (a MediaSource blob).
const VIDEO_SRC = 'blob:https://m.youtube.com/video-1';
const AD_SRC = 'blob:https://m.youtube.com/ad-1';

/**
 * A watch page whose player can show an ad, with a Skip button in it. As on
 * a real page, the page has already read its video's player data (213 s),
 * unless `playerData: false`; `playerData: {...}` changes what it says. The
 * player's element holds the video's stream.
 */
function adPage(opts = {}) {
  const p = makePage(opts);
  p.player.classList.add('html5-video-player');
  p.video.currentSrc = VIDEO_SRC;
  const skip = new Element('button', p.player);
  p.selectors['.ytp-ad-skip-button-modern'] = skip;
  if (opts.playerData !== false) seePlayerData(p, opts.playerData || {});
  return { p, skip };
}

/** A mid-roll: the element loads the ad's own stream and the class comes on. */
function adBegins(p, adSeconds = 15) {
  p.video.currentSrc = AD_SRC;
  p.video.duration = adSeconds;
  p.video.currentTime = 0;
  p.player.classList.add('ad-showing');
  p.mutated(p.player);
}

function adEnds(p, { position = 60 } = {}) {
  p.video.currentSrc = VIDEO_SRC;
  p.video.duration = 213.5;
  p.video.currentTime = position;
  p.video.ended = false;
  p.video.paused = false;
  p.player.classList.remove('ad-showing');
  p.mutated(p.player);
}

test('Block ads: a mid-roll ad is muted, run to its end and skipped; the sound comes back after', () => {
  const { p, skip } = adPage();
  p.video.currentTime = 60;
  playing(p);
  // One observer, on the player's class only.
  const watching = p.env.observers.filter((o) => o.target === p.player);
  assert.equal(watching.length, 1);
  assert.deepEqual(Array.from(watching[0].options.attributeFilter), ['class']);
  adBegins(p);
  assert.equal(p.video.muted, true);
  assert.equal(p.video.currentTime, 15, 'run to its end');
  assert.equal(skip.clicks, 1);
  adEnds(p);
  assert.equal(p.video.muted, false, 'the sound comes back');
  assert.equal(adStats(p).adBreaks, 1);
  // No polling: still only the keep-alive minute.
  assert.equal(p.env.intervals.length, 1);
});

test('Block ads: while an ad is skipped the notification keeps the video, and never hears a pause or a seek', () => {
  const { p } = adPage();
  p.video.currentTime = 60;
  playing(p);
  p.env.posted.length = 0;
  adBegins(p);
  // YouTube names the ad in the media session while it plays.
  vm.runInContext(
    "navigator.mediaSession.metadata = new MediaMetadata({ title: 'Mentos Mini Rainbow', artist: 'Mentos' });",
    p.context
  );
  p.flushTimers();
  p.dispatch(p.video, 'seeked');
  p.video.paused = true;
  p.video.ended = true;
  p.dispatch(p.video, 'pause');
  p.dispatch(p.video, 'ended');
  const during = p.media();
  assert.ok(during.length >= 2);
  for (const m of during) {
    assert.equal(m.t, TOKEN);
    assert.equal(m.e, 'ad', 'never "pause", "seeked" or "ended"');
    assert.equal(m.s, 'buffering');
    assert.equal(m.ti, 'Never Gonna Give You Up');
    assert.notEqual(m.ar, 'Mentos');
    assert.equal(m.p, 60, "the video's own position");
    assert.equal(m.d, 213.5, "the video's own length");
    assert.equal(m.r, 1);
    assert.equal(m.yp, false);
  }
  adEnds(p, { position: 60 });
  const after = p.media().pop();
  assert.equal(after.e, 'adend');
  assert.equal(after.s, 'playing');
  assert.equal(after.ti, 'Never Gonna Give You Up', "the ad's title never shows, even after it");
  assert.ok(p.media().every((m) => m.ti !== 'Mentos Mini Rainbow'));
});

test('Block ads: a pre-roll on a new page is muted and skipped, never run to its end, and never named', () => {
  const { p, skip } = adPage();
  p.env.posted.length = 0;
  // The player starts with the ad, and the page names it just before its video loads.
  p.player.classList.add('ad-showing');
  vm.runInContext("navigator.mediaSession.metadata = new MediaMetadata({ title: 'Mentos Mini Rainbow' });", p.context);
  p.video.currentSrc = AD_SRC;
  p.video.duration = 15;
  p.video.play();
  p.dispatch(p.video, 'loadedmetadata');
  p.dispatch(p.video, 'play');
  p.flushTimers();
  assert.equal(p.video.muted, true);
  // Nothing showed the video itself playing in this player first: it could
  // be the video with an ad stitched in, or the next video, so no seek.
  assert.equal(p.video.currentTime, 0);
  assert.ok(skip.clicks >= 1);
  p.video.currentSrc = VIDEO_SRC;
  adEnds(p, { position: 0 });
  p.dispatch(p.video, 'playing');
  const all = p.media();
  assert.ok(all.length >= 1);
  assert.ok(all.every((m) => m.ti === 'Never Gonna Give You Up'), JSON.stringify(all.map((m) => m.ti)));
  assert.equal(all.pop().s, 'playing');
});

test("Block ads: the video's own metadata, set while the ad class lingers, is kept for after", () => {
  const { p } = adPage({ nativeMediaSession: true });
  p.video.currentTime = 60;
  playing(p);
  adBegins(p);
  // The page names the video itself (its title is the page's) before the class goes.
  vm.runInContext(
    "navigator.mediaSession.metadata = new MediaMetadata({ title: 'Never Gonna Give You Up', artist: 'Rick Astley' });",
    p.context
  );
  assert.equal(p.env.native.metadataSet.title, 'Never Gonna Give You Up', "reaches the phone's own session too");
  adEnds(p);
  const after = p.media().pop();
  assert.equal(after.ar, 'Rick Astley');
  // An ad's metadata never reaches the browser's own session (iOS lock screen).
  adBegins(p);
  vm.runInContext("navigator.mediaSession.metadata = new MediaMetadata({ title: 'Mentos Mini Rainbow' });", p.context);
  assert.equal(p.env.native.metadataSet.title, 'Never Gonna Give You Up');
});

test('Block ads: a pause the viewer makes during an ad still shows as a pause (of the video)', () => {
  const { p } = adPage();
  p.video.currentTime = 60;
  playing(p);
  adBegins(p);
  assert.equal(p.command('pause'), true);
  p.dispatch(p.video, 'pause');
  const m = p.media().pop();
  assert.equal(m.s, 'paused');
  assert.equal(m.e, 'ad');
  assert.equal(m.ti, 'Never Gonna Give You Up');
});

test('Block ads: the ad class lingering while the video itself loads never runs the video to its end', () => {
  const { p, skip } = adPage();
  vm.runInContext(`window.ytInitialPlayerResponse = ${JSON.stringify(playerJson({ lengthSeconds: '213' }))};`, p.context);
  p.video.currentTime = 30;
  playing(p);
  p.player.classList.add('ad-showing'); // the video's own 213.5 s are loaded under it
  p.mutated(p.player);
  p.dispatch(p.video, 'timeupdate');
  assert.equal(p.video.currentTime, 30);
  assert.equal(p.video.muted, false);
  assert.equal(skip.clicks, 0);
});

/** The ad class is on (or stays on) while the player's media is [seconds] long. */
function adClassOver(p, seconds, { position = 30, src } = {}) {
  p.video.duration = seconds;
  p.video.currentTime = position;
  if (src !== undefined) p.video.currentSrc = src;
  p.player.classList.add('ad-showing');
  p.mutated(p.player);
  p.dispatch(p.video, 'timeupdate');
}

function classGoes(p) {
  p.player.classList.remove('ad-showing');
  p.mutated(p.player);
}

test('Block ads: no video in the address (mini player on Home or Search, YouTube Music browsing): the video is never run to its end', () => {
  for (const href of [
    'https://m.youtube.com/',
    'https://m.youtube.com/results?search_query=lofi',
    'https://music.youtube.com/',
    'https://music.youtube.com/library',
  ]) {
    const { p } = adPage({ href });
    p.video.currentTime = 30;
    playing(p);
    // The video itself (213.5 s, its player data seen) under a lingering class.
    adClassOver(p, 213.5);
    assert.equal(p.video.currentTime, 30, href);
    classGoes(p);
    assert.equal(p.video.muted, false, `${href}: the sound comes back`);
    assert.equal(p.video.currentTime, 30, href);

    // A real ad there: muted and its Skip pressed, never run to its end (the page's video is not known).
    const { p: q, skip } = adPage({ href });
    q.video.currentTime = 30;
    playing(q);
    adClassOver(q, 15, { position: 2 });
    assert.equal(q.video.muted, true, href);
    assert.ok(skip.clicks >= 1, href);
    assert.equal(q.video.currentTime, 2, href);
    classGoes(q);
    assert.equal(q.video.muted, false, href);
  }
});

test('Block ads: the address still names the last video while the next one loads: the next one is never run to its end', () => {
  // Autoplay or a playlist: the next video's player data (300 s) is read, its
  // stream loads under the lingering class, and the address is not updated yet.
  const { p } = adPage();
  p.video.currentTime = 200;
  playing(p);
  seePlayerData(p, { videoId: 'AAAAAAAAAAA', lengthSeconds: '300' });
  adClassOver(p, 300.4, { position: 0 });
  assert.equal(p.video.currentTime, 0);
  classGoes(p);
  assert.equal(p.video.muted, false);

  // A shorter next video (120 s) the same way.
  seePlayerData(p, { videoId: 'BBBBBBBBBBB', lengthSeconds: '120' });
  adClassOver(p, 120.4, { position: 0 });
  assert.equal(p.video.currentTime, 0);
  classGoes(p);
  assert.equal(p.video.muted, false);
});

test('Block ads: after the ad, another stream under the same class is never run to its end', () => {
  const { p } = adPage();
  p.video.currentTime = 60;
  p.video.currentSrc = 'blob:https://m.youtube.com/video-1';
  playing(p);
  adClassOver(p, 15, { position: 0, src: 'blob:https://m.youtube.com/ad-1' });
  assert.equal(p.video.currentTime, 15, 'the ad itself is run to its end');
  // The class stays while a video whose player data was never seen (120 s) loads.
  adClassOver(p, 120.4, { position: 0, src: 'blob:https://m.youtube.com/video-2' });
  assert.equal(p.video.currentTime, 0);
  assert.equal(p.video.muted, true, 'muted at most, while the class shows');
  classGoes(p);
  assert.equal(p.video.muted, false);
});

test('Block ads: an ad stitched into the video\'s own stream: never run to its end, only muted and skipped', () => {
  // Server-side ads: one stream, the ad (15 s) and the video (213 s) together.
  const { p, skip } = adPage();
  playing(p);
  adClassOver(p, 228.5, { position: 3 });
  assert.equal(p.video.currentTime, 3, 'the video in the same stream is not lost');
  assert.equal(p.video.muted, true);
  assert.ok(skip.clicks >= 1);
  p.video.currentTime = 18; // the ad part is over
  classGoes(p);
  assert.equal(p.video.muted, false);
  assert.equal(p.video.currentTime, 18);
});

test('Block ads: the next video with an ad stitched into its stream, the address still naming the last one: never run to its end', () => {
  // Autoplay or a playlist, on both sites. The next video's own stream starts
  // with an ad stitched in (so it is longer than its player data says), the
  // ad class is on, and the address has not caught up. A long next video, and
  // one short enough to pass for an ad nobody can skip.
  const VIDEO_2 = 'blob:https://m.youtube.com/video-2';
  for (const href of ['https://m.youtube.com/watch?v=dQw4w9WgXcQ', 'https://music.youtube.com/watch?v=dQw4w9WgXcQ']) {
    for (const [len, stream] of [['120', 135.2], ['20', 26.2]]) {
      // ended: the last video played to its end, then the next one's player data came;
      // tapped: the viewer chose the next video halfway through the last one;
      // unseen: the last video ended and the next one's player data was never seen.
      for (const how of ['ended', 'tapped', 'unseen']) {
        const where = `${href}, ${len} s, ${how}`;
        const { p, skip } = adPage({ href });
        p.video.currentTime = 60;
        playing(p);
        p.dispatch(p.video, 'timeupdate');
        if (how !== 'tapped') {
          p.video.currentTime = 213.5;
          p.video.ended = true;
          p.video.paused = true;
          p.dispatch(p.video, 'ended');
        }
        if (how !== 'unseen') seePlayerData(p, { videoId: 'BBBBBBBBBBB', lengthSeconds: len });
        Object.assign(p.video, { currentSrc: VIDEO_2, duration: stream, currentTime: 0, ended: false, paused: false });
        p.player.classList.add('ad-showing');
        p.mutated(p.player);
        p.dispatch(p.video, 'durationchange');
        p.dispatch(p.video, 'timeupdate');
        assert.equal(p.video.currentTime, 0, `${where}: the next video is not lost`);
        assert.equal(p.video.muted, true, where);
        assert.ok(skip.clicks >= 1, where);
        p.video.currentTime = 7; // the stitched ad is over
        classGoes(p);
        assert.equal(p.video.muted, false, `${where}: the sound comes back`);
        assert.equal(p.video.currentTime, 7, where);
      }
    }
  }
});

test('Block ads: a mid-roll is run to its end only right after the video played in that element, and only a short one', () => {
  // The address moved on to another video during the break.
  const { p } = adPage();
  seePlayerData(p, { videoId: 'BBBBBBBBBBB', lengthSeconds: '120' });
  seePlayerData(p); // the address's own video, seen last
  p.video.currentTime = 60;
  playing(p);
  p.win.location.href = 'https://m.youtube.com/watch?v=BBBBBBBBBBB';
  adBegins(p);
  assert.equal(p.video.currentTime, 0, 'after an address change');
  assert.equal(p.video.muted, true);

  // The video was at its very end (a post-roll, or the next video coming).
  const { p: q } = adPage();
  q.video.currentTime = 210;
  playing(q);
  adBegins(q);
  assert.equal(q.video.currentTime, 0, 'at the end of the video');
  assert.equal(q.video.muted, true);

  // A long ad (45 s): YouTube lets it be skipped, so Skip is pressed instead.
  const { p: r, skip } = adPage();
  r.video.currentTime = 60;
  playing(r);
  adBegins(r, 45);
  assert.equal(r.video.currentTime, 0, 'a long ad');
  assert.equal(r.video.muted, true);
  assert.ok(skip.clicks >= 1);

  // The same short mid-roll right after the video played: run to its end.
  const { p: s } = adPage();
  s.video.currentTime = 60;
  playing(s);
  adBegins(s, 30);
  assert.equal(s.video.currentTime, 30);
});

test("Block ads: when the break's first stream was only muted, no later stream under the same class is run to its end", () => {
  const VIDEO_2 = 'blob:https://m.youtube.com/video-2';
  // First: a long skippable ad (240 s, longer than the video), or an ad as
  // long as another video seen (15 s): both only muted, Skip pressed.
  for (const first of [{ seconds: 240 }, { seconds: 15.2, other: '15' }]) {
    // Then, still under the class: a next video whose player data was never
    // seen (120 s), or a short stream (a second ad, or a short next video).
    for (const next of [120.4, 20]) {
      const where = `${first.seconds} s, then ${next} s`;
      const { p, skip } = adPage();
      if (first.other) {
        seePlayerData(p, { videoId: 'CCCCCCCCCCC', lengthSeconds: first.other });
        seePlayerData(p); // the address's own video, seen last
      }
      p.video.currentTime = 60;
      playing(p);
      adClassOver(p, first.seconds, { position: 0, src: AD_SRC });
      assert.equal(p.video.currentTime, 0, `${where}: the first one is only muted`);
      assert.equal(p.video.muted, true, where);
      adClassOver(p, next, { position: 0, src: VIDEO_2 });
      assert.equal(p.video.currentTime, 0, `${where}: never run to its end`);
      assert.equal(p.video.muted, true, where);
      assert.ok(skip.clicks >= 1, where);
      classGoes(p);
      assert.equal(p.video.muted, false, where);
    }
  }
});

test('Block ads: before the length is known, or without player data, nothing is run to its end', () => {
  const { p } = adPage({ playerData: false });
  playing(p);
  adClassOver(p, 15, { position: 1 });
  assert.equal(p.video.currentTime, 1);
  assert.equal(p.video.muted, true);
  const { p: q } = adPage();
  playing(q);
  adClassOver(q, NaN, { position: 0, src: AD_SRC });
  assert.equal(q.video.currentTime, 0);
  assert.equal(q.video.muted, true);
  // Its length arrives: now it is surely the ad.
  q.video.duration = 15;
  q.dispatch(q.video, 'durationchange');
  assert.equal(q.video.currentTime, 15);
  // Or it turns out to be the video itself (the class lingers): the sound comes back at once.
  const { p: r } = adPage();
  playing(r);
  adClassOver(r, NaN, { position: 0 });
  assert.equal(r.video.muted, true);
  r.video.duration = 213.5;
  r.dispatch(r.video, 'durationchange');
  assert.equal(r.video.muted, false);
  assert.equal(r.video.currentTime, 0);
});

test("Block ads: YouTube Music: the song's own title and artist stay after an ad", () => {
  const href = 'https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=RDAMVM';
  const title = 'Never Gonna Give You Up - YouTube Music';
  // Set just before the ad.
  const { p } = adPage({ href, title });
  p.video.currentTime = 60;
  playing(p);
  vm.runInContext(
    "navigator.mediaSession.metadata = new MediaMetadata({ title: 'Never Gonna Give You Up', artist: 'Rick Astley' });",
    p.context
  );
  p.flushTimers();
  p.env.now += 500;
  adBegins(p);
  p.dispatch(p.video, 'timeupdate');
  assert.equal(p.media().pop().e, 'ad');
  adEnds(p);
  let after = p.media().pop();
  assert.equal(after.e, 'adend');
  assert.equal(after.ti, 'Never Gonna Give You Up');
  assert.equal(after.ar, 'Rick Astley');

  // Set while the class lingers after the ad.
  const { p: q } = adPage({ href, title, nativeMediaSession: true });
  q.video.currentTime = 60;
  playing(q);
  adBegins(q);
  vm.runInContext(
    "navigator.mediaSession.metadata = new MediaMetadata({ title: 'Never Gonna Give You Up', artist: 'Rick Astley' });",
    q.context
  );
  assert.equal(q.env.native.metadataSet.title, 'Never Gonna Give You Up', "reaches the phone's own session too");
  adEnds(q);
  after = q.media().pop();
  assert.equal(after.ti, 'Never Gonna Give You Up');
  assert.equal(after.ar, 'Rick Astley');

  // The ad's own, set while it plays, is still never shown.
  adBegins(q);
  vm.runInContext("navigator.mediaSession.metadata = new MediaMetadata({ title: 'Mentos Mini Rainbow', artist: 'Mentos' });", q.context);
  adEnds(q);
  after = q.media().pop();
  assert.notEqual(after.ti, 'Mentos Mini Rainbow');
  assert.notEqual(after.ar, 'Mentos');
});

test("Block ads: without a MutationObserver the video's own events start the skip", () => {
  const { p, skip } = adPage();
  p.win.MutationObserver = undefined;
  playing(p);
  p.video.currentSrc = AD_SRC;
  p.video.duration = 20;
  p.player.classList.add('ad-interrupting');
  p.dispatch(p.video, 'durationchange');
  assert.equal(p.video.muted, true);
  assert.equal(p.video.currentTime, 20);
  assert.equal(skip.clicks, 1);
  p.player.classList.remove('ad-interrupting');
  p.dispatch(p.video, 'timeupdate');
  assert.equal(p.video.muted, false);
});

test('Block ads: ad boxes are hidden by one style sheet, each :has() rule on its own', () => {
  const p = makePage();
  const styles = adsStyle(p);
  assert.equal(styles.length, 1);
  const css = styles[0].textContent;
  for (const sel of [
    'ytm-promoted-sparkles-web-renderer',
    'ytm-promoted-video-renderer',
    'ytm-companion-ad-renderer',
    'ytm-companion-slot',
    'ad-slot-renderer',
    'ytm-ad-slot-renderer',
    'ytm-statement-banner-renderer',
    '.ytp-ad-overlay-container',
    'ytd-enforcement-message-view-model',
  ]) {
    assert.ok(css.includes(sel), sel);
  }
  const rules = css.split('}').filter(Boolean);
  for (const rule of rules) assert.ok(rule.endsWith('{display:none!important'), rule);
  const selectors = rules.map((r) => r.split('{')[0]);
  for (const s of selectors.filter((sel) => sel.includes(':has('))) {
    assert.ok(!s.includes(','), `${s}: a browser without :has() must drop this rule alone`);
  }
  // Never the player, the video or the Skip button.
  for (const s of selectors.join(',').split(',')) {
    assert.ok(!/^(video|iframe|\.html5-video-player|#movie_player|\.ytp-ad-module|\.video-ads)$/.test(s.trim()), s);
    assert.ok(!/skip/.test(s), s);
  }
  // The picture-in-picture style is separate and untouched.
  assert.equal(p.head.children.filter((c) => c.tagName === 'STYLE').length, 0);
});

test('Block ads: no <html> element at document start: the style goes in as soon as there is one', () => {
  const p = makePage({ noDocumentElement: true });
  assert.equal(adsStyle(p).length, 0);
  p.attachDocumentElement();
  assert.equal(adsStyle(p).length, 1);
  p.attachDocumentElement();
  assert.equal(adsStyle(p).length, 1, 'once');
});

test('Block ads: requests to ad addresses fail like a blocked request; the video and the player API go through', async () => {
  const p = makePage();
  const fetchIn = (url) => vm.runInContext(`fetch(${JSON.stringify(url)})`, p.context);
  const ads = [
    'https://googleads.g.doubleclick.net/pagead/id',
    'https://static.doubleclick.net/instream/ad_status.js',
    'https://www.googleadservices.com/pagead/conversion/1001/',
    'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js',
    'https://imasdk.googleapis.com/js/sdkloader/ima3.js',
    'https://www.googletagservices.com/tag/js/gpt.js',
    'https://m.youtube.com/pagead/viewthroughconversion/962985656/?backend=innertube',
    'https://www.youtube.com/api/stats/ads?ver=2&ns=1',
    '/api/stats/ads?ver=2',
    '/pagead/adview?ai=x',
    'https://www.youtube.com/ptracking?ptk=youtube_none',
    '//www.youtube.com/get_midroll_info?ei=x',
    'HTTPS://GOOGLEADS.G.DOUBLECLICK.NET/pagead/id',
  ];
  for (const url of ads) await assert.rejects(fetchIn(url), (e) => e.name === 'TypeError', url);
  assert.deepEqual(p.env.fetched, []);
  const keep = [
    'https://rr1---sn-ab5l6nzr.googlevideo.com/videoplayback?expire=1&id=o-x&itag=251&source=youtube&ctier=L&oad=1',
    'https://m.youtube.com/youtubei/v1/player?prettyPrint=false',
    '/youtubei/v1/next?prettyPrint=false',
    'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
    'https://yt3.ggpht.com/ytc/abc=s88',
    'https://www.youtube.com/api/stats/watchtime?ns=yt',
    'https://www.youtube.com/api/stats/playback?ns=yt',
    'https://s.youtube.com/api/stats/qoe?event=streamingstats',
    'https://jnn-pa.googleapis.com/$rpc/google.internal.waa.v1.Waa/GenerateIT',
    'https://www.youtube.com/watch?v=dQw4w9WgXcQ&next=/pagead/x',
    'https://doubleclick.net.example.org/pagead/id',
  ];
  for (const url of keep) assert.equal(await fetchIn(url), 'answer', url);
  assert.deepEqual(p.env.fetched, keep);
  // A Request object counts by its address.
  await assert.rejects(vm.runInContext("fetch({ url: 'https://googleads.g.doubleclick.net/pagead/id' })", p.context));
  // sendBeacon: "queued", nothing sent.
  assert.equal(vm.runInContext("navigator.sendBeacon('https://www.youtube.com/api/stats/ads?x=1')", p.context), true);
  assert.equal(vm.runInContext("navigator.sendBeacon('https://www.youtube.com/api/stats/qoe?x=1')", p.context), true);
  assert.deepEqual(p.env.beacons, ['https://www.youtube.com/api/stats/qoe?x=1']);
  // XHR: an error, no answer; the same object reused for a normal request works as before.
  const xhr = vm.runInContext(
    "var x = new XMLHttpRequest(); x.open('GET', 'https://googleads.g.doubleclick.net/pagead/id'); x.send(); x",
    p.context
  );
  assert.deepEqual(p.env.xhrSent, []);
  p.flushTimers();
  assert.deepEqual(xhr.events, ['readystatechange', 'error', 'loadend']);
  assert.equal(xhr.readyState, 4);
  vm.runInContext("x.open('POST', '/youtubei/v1/player'); x.send('{}');", p.context);
  assert.deepEqual(p.env.xhrSent, ['/youtubei/v1/player']);
  assert.equal(xhr.readyState, 1);
  assert.equal(adStats(p).blocked, ads.length + 3);
});

test('Block ads off: the page is left exactly as it was', async () => {
  const p = makePage({ blockAds: false });
  p.player.classList.add('html5-video-player');
  const skip = new Element('button', p.player);
  p.selectors['.ytp-ad-skip-button-modern'] = skip;
  assert.equal(adStats(p).on, false);
  // Player data keeps its ads.
  assert.ok(Array.isArray(parseInPage(p, JSON.stringify(playerJson())).adPlacements));
  const R = p.win.Response;
  const answer = await new R(JSON.stringify(playerJson()), 'https://m.youtube.com/youtubei/v1/player').json();
  assert.ok(Array.isArray(answer.playerAds));
  assert.equal(Object.getOwnPropertyDescriptor(p.win, 'ytInitialPlayerResponse'), undefined);
  assert.equal(adsStyle(p).length, 0);
  // Requests go out.
  assert.equal(await vm.runInContext("fetch('https://googleads.g.doubleclick.net/pagead/id')", p.context), 'answer');
  vm.runInContext("navigator.sendBeacon('https://www.youtube.com/api/stats/ads?x=1')", p.context);
  assert.equal(p.env.beacons.length, 1);
  // An ad plays as YouTube shows it, and is reported as before.
  p.video.currentTime = 60;
  playing(p);
  p.video.duration = 15;
  p.video.currentTime = 0;
  p.player.classList.add('ad-showing');
  p.dispatch(p.video, 'timeupdate');
  assert.equal(p.env.observers.length, 0);
  assert.equal(p.video.muted, false);
  assert.equal(p.video.currentTime, 0);
  assert.equal(skip.clicks, 0);
  vm.runInContext("navigator.mediaSession.metadata = new MediaMetadata({ title: 'Mentos Mini Rainbow' });", p.context);
  p.flushTimers();
  assert.equal(p.media().pop().ti, 'Mentos Mini Rainbow');
});

test('Block ads: the bare asset blocks (only "off" turns it off)', () => {
  const p = makePage({ rawBlockAds: true });
  assert.equal(adStats(p).on, true);
  assert.equal(adsStyle(p).length, 1);
});

test('Block ads: never on another site, the sign-in pages or in an iframe', () => {
  for (const opts of [
    { href: 'https://accounts.google.com/v3/signin/identifier' },
    { href: 'https://accounts.youtube.com/accounts/SetSID' },
    { href: 'https://evil.example/watch?v=dQw4w9WgXcQ' },
    { inIframe: true },
  ]) {
    const p = makePage(opts);
    assert.ok(Array.isArray(parseInPage(p, JSON.stringify(playerJson())).adPlacements), JSON.stringify(opts));
    assert.equal(adsStyle(p).length, 0);
    assert.equal(p.env.observers.length, 0);
  }
});
