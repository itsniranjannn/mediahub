// MediaHub media bridge for the Online (YouTube) tab.
//
// Injected by lib/features/online at document start, main frame only. It:
//  (a) keeps the page believing it is visible while "Background play" is on,
//      so YouTube does not pause when the screen turns off or the app leaves
//      the foreground;
//  (b) wraps (or, where the WebView has none, provides) navigator.mediaSession
//      to learn the title, channel, artwork and the page's own play / next /
//      previous handlers;
//  (c) watches the main <video> (play, pause, ended, metadata, rate, 1 s ticks)
//      and posts compact JSON to Dart through flutter_inappwebview;
//  (d) runs commands from Dart (play, pause, seekTo, next, previous ...);
//  (e) picture-in-picture helpers: an html class that makes the playing video
//      fill the window (Android PiP), and the browser's own PiP on iOS;
//  (f) keep-alive while "Background play" is on: YouTube's last-activity
//      clock (window._lact) is refreshed every minute, and its "Continue
//      watching?" prompt is confirmed when it paused the video by itself;
//  (g) ad blocking (Settings → Online → Block ads): the player's data loses
//      its ad fields, an ad that still plays is muted and its Skip pressed
//      (and run to its end only when it is surely a mid-roll ad), ad boxes
//      are hidden by a style sheet, and the page's ad requests fail.
//
// Every message carries the token Dart put in place of the placeholder below;
// Dart drops messages without it. Nothing here may ever throw into the page:
// YouTube's markup changes often, so every DOM lookup is optional.
// Tests: node test/js/youtube_bridge_test.js
(function () {
  'use strict';
  var TOKEN = '__MEDIAHUB_BRIDGE_TOKEN__';
  // Settings → Online → Block ads: Dart puts 'on' or 'off' here with the
  // token. It must be known before YouTube's first script runs, so a change
  // takes a fresh page (the Online tab opens the page again). Anything but
  // 'off' (the bare asset too) blocks.
  var BLOCK_ADS = '__MEDIAHUB_BLOCK_ADS__' !== 'off';
  var HANDLER = 'mediahubBridge';
  var PIP_CLASS = 'mediahub-pip';
  var PIP_VIDEO_CLASS = 'mediahub-pip-video';
  var PIP_ANCESTOR_CLASS = 'mediahub-pip-ancestor';
  var TICK_MS = 1000;
  var DEDUPE_MS = 800;
  var KEEPALIVE_MS = 60000;
  // A pause this soon after the user touched the page is the user's own.
  var INPUT_GRACE_MS = 5000;
  var MAX_QUERY = 200;

  var w = typeof window !== 'undefined' ? window : null;
  if (!w) return;
  try {
    if (w.top !== w) return; // main frame only (iframes never get the bridge)
  } catch (e) {
    return; // cross-origin parent: certainly not the main frame
  }
  // https YouTube pages only. The WebView is told to inject into those
  // origins alone, but iOS ignores that list and Android's fallback for older
  // WebViews injects everywhere, so the script checks for itself: any other
  // page never sees the token. Google's sign-in pages (accounts.google.com,
  // and accounts.youtube.com, the hop that hands a sign-in to YouTube) load
  // in the tab too, but never get the bridge.
  try {
    var loc = w.location;
    var host = String(loc.hostname || '').toLowerCase();
    if (String(loc.protocol) !== 'https:' || !/(^|\.)youtube\.com$/.test(host)) return;
    if (host === 'accounts.youtube.com') return;
  } catch (e) {
    return;
  }
  if (w.__mediahubBridge) return; // already installed in this document
  var doc = w.document;
  if (!doc) return;

  // Captured now, before any page script runs: a page that later swaps these
  // for wrappers never sees a message (or its token).
  var reflectApply = typeof Reflect === 'object' && Reflect && typeof Reflect.apply === 'function' ? Reflect.apply : null;
  var dateNow = Date.now;
  var platform = null; // { obj, call }: flutter_inappwebview and its callHandler, captured once

  function capturePlatform() {
    if (platform) return true;
    try {
      var b = w.flutter_inappwebview;
      if (b && typeof b.callHandler === 'function') {
        platform = { obj: b, call: b.callHandler };
        return true;
      }
    } catch (e) {
      // a getter that throws: no bridge yet
    }
    return false;
  }
  capturePlatform();

  function invoke(fn, self, args) {
    if (reflectApply) return reflectApply(fn, self, args);
    return fn.apply(self, args);
  }

  function now() {
    return invoke(dateNow, Date, []);
  }

  function safe(fn, fallback) {
    try {
      return fn();
    } catch (e) {
      return fallback;
    }
  }

  var state = {
    background: true, // "Background play" (Dart sets it right after injection)
    pipLayout: false,
    autoPip: true,
    lastTick: 0,
    lastKey: '',
    video: null,
    pending: null,
    ready: false,
    handlers: {}, // page media session action handlers
    nativeAt: {}, // when the browser itself last invoked an action handler (iOS lock screen)
    bridgeAt: {}, // when Dart last invoked one
    metadata: null, // what the page last set
    metadataIsAd: false, // ... and it was an ad's (never shown in the notification)
    lastContent: null, // the last message about the video itself (not an ad)
    lastInputAt: 0, // the user's last touch, click or key in the page
    bridgePausing: false, // our own pause command is running
    scriptPauseAt: 0, // page script paused a media element (not us)
    scriptPauseEl: null, // ... and which one
    idlePauseAt: 0, // the page paused the main video by itself (no user input before it)
  };

  // ---------------------------------------------------------------------------
  // (a) Background play: the page always looks visible and focused.
  // ---------------------------------------------------------------------------
  var DocProto = safe(function () {
    return w.Document && w.Document.prototype;
  }, null);

  function nativeGetter(name) {
    var proto = DocProto;
    while (proto) {
      var d = safe(function () {
        return Object.getOwnPropertyDescriptor(proto, name);
      }, null);
      if (d && d.get) return d.get;
      proto = safe(function () {
        return Object.getPrototypeOf(proto);
      }, null);
    }
    return null;
  }

  function spoofProperty(name, visibleValue) {
    var original = nativeGetter(name);
    safe(function () {
      Object.defineProperty(doc, name, {
        configurable: true,
        enumerable: true,
        get: function () {
          if (state.background) return visibleValue;
          return original ? original.call(doc) : visibleValue;
        },
      });
    });
  }

  function reallyHidden() {
    var g = nativeGetter('hidden');
    return g ? !!safe(function () { return g.call(doc); }, false) : false;
  }

  spoofProperty('hidden', false);
  spoofProperty('webkitHidden', false);
  spoofProperty('visibilityState', 'visible');
  spoofProperty('webkitVisibilityState', 'visible');

  safe(function () {
    var originalHasFocus = doc.hasFocus;
    doc.hasFocus = function () {
      if (state.background) return true;
      return typeof originalHasFocus === 'function' ? originalHasFocus.call(doc) : true;
    };
  });

  // YouTube takes a window much smaller than the screen for picture-in-
  // picture (on every resize it compares outerWidth x outerHeight with the
  // screen) and then pauses, since playing in a small window is a Premium
  // feature. Android's picture-in-picture shrinks the whole window, so the
  // video stopped a moment after it entered the floating window (seen on the
  // emulator with real YouTube; the stand-in page has no such check). The
  // page is told the window is at least as large as the screen. Only the
  // outer size changes: the layout (innerWidth, media queries) still follows
  // the real window.
  ['outerWidth', 'outerHeight'].forEach(function (name) {
    safe(function () {
      var desc = Object.getOwnPropertyDescriptor(w, name) ||
        (w.Window && w.Window.prototype && Object.getOwnPropertyDescriptor(w.Window.prototype, name));
      var getter = desc && desc.get;
      var plain = desc && !getter ? desc.value : undefined;
      Object.defineProperty(w, name, {
        configurable: true,
        enumerable: true,
        get: function () {
          var real = getter ? safe(function () { return getter.call(w); }, 0) : plain;
          var screenSize = safe(function () {
            return w.screen ? (name === 'outerWidth' ? w.screen.width : w.screen.height) : 0;
          }, 0);
          return Math.max(typeof real === 'number' ? real : 0, typeof screenSize === 'number' ? screenSize : 0);
        },
      });
    });
  });

  function swallow(event) {
    if (!state.background) return;
    var t = event && event.type;
    // blur / focusout on elements (an input losing focus) must still reach
    // the page; only the window / document losing focus is hidden.
    if ((t === 'blur' || t === 'focusout') && event.target !== w && event.target !== doc) return;
    safe(function () {
      event.stopImmediatePropagation();
    });
  }

  ['visibilitychange', 'webkitvisibilitychange', 'pagehide', 'blur', 'freeze'].forEach(function (type) {
    safe(function () {
      w.addEventListener(type, swallow, true);
    });
    safe(function () {
      doc.addEventListener(type, swallow, true);
    });
  });

  // Who paused the video? The user's own touches and keys are noted, and the
  // page's script calls to pause() are told apart from ours, so a pause the
  // page made by itself (YouTube's idle "Continue watching?" stop) can be
  // reported as such. A pause the browser makes (audio focus, a phone call)
  // goes through neither and is never taken for one.
  function onInput(event) {
    if (event && event.isTrusted === false) return; // a script's synthetic event
    state.lastInputAt = now();
  }
  ['pointerdown', 'touchstart', 'mousedown', 'keydown'].forEach(function (type) {
    safe(function () {
      doc.addEventListener(type, onInput, { capture: true, passive: true });
    });
  });

  safe(function () {
    var proto = w.HTMLMediaElement && w.HTMLMediaElement.prototype;
    var original = proto && proto.pause;
    if (typeof original !== 'function') return;
    proto.pause = function () {
      if (!state.bridgePausing) {
        state.scriptPauseAt = now();
        state.scriptPauseEl = this;
      }
      return invoke(original, this, []);
    };
  });

  // ---------------------------------------------------------------------------
  // (b) Media session: capture metadata and the page's action handlers.
  // ---------------------------------------------------------------------------
  var ACTIONS = ['play', 'pause', 'nexttrack', 'previoustrack', 'seekto', 'seekbackward', 'seekforward', 'stop'];
  var nav = w.navigator || {};

  if (typeof w.MediaMetadata !== 'function') {
    safe(function () {
      w.MediaMetadata = function MediaMetadata(init) {
        init = init || {};
        this.title = init.title ? String(init.title) : '';
        this.artist = init.artist ? String(init.artist) : '';
        this.album = init.album ? String(init.album) : '';
        this.artwork = Array.isArray(init.artwork) ? init.artwork.slice() : [];
      };
    });
  }

  function wrapHandler(action, handler) {
    return function (details) {
      // The browser invoked it (iOS lock screen / Control Center). If Dart sent
      // the same action a moment ago, this is the same press seen twice.
      var t = now();
      if (state.bridgeAt[action] && t - state.bridgeAt[action] < DEDUPE_MS) return undefined;
      state.nativeAt[action] = t;
      return handler.call(this, details);
    };
  }

  function installMediaSession() {
    var ms = nav.mediaSession;
    var nativeSet = null;
    var metaDesc = null;
    var protoOfMs = null;
    if (ms) {
      nativeSet = typeof ms.setActionHandler === 'function' ? ms.setActionHandler : null;
      protoOfMs = safe(function () {
        return Object.getPrototypeOf(ms);
      }, null);
      metaDesc = protoOfMs
        ? safe(function () {
            return Object.getOwnPropertyDescriptor(protoOfMs, 'metadata');
          }, null)
        : null;
    } else {
      ms = { playbackState: 'none' };
      safe(function () {
        Object.defineProperty(nav, 'mediaSession', { configurable: true, enumerable: true, value: ms });
      });
      if (nav.mediaSession !== ms) return; // navigator is locked down: nothing to capture
    }

    safe(function () {
      ms.setActionHandler = function (action, handler) {
        if (ACTIONS.indexOf(action) < 0 && !nativeSet) return undefined;
        if (typeof handler === 'function') {
          state.handlers[action] = handler;
        } else {
          delete state.handlers[action];
        }
        if (nativeSet) {
          try {
            nativeSet.call(ms, action, typeof handler === 'function' ? wrapHandler(action, handler) : null);
          } catch (e) {
            // unsupported action in this browser: still captured for Dart
          }
        }
        schedulePost('session');
        return undefined;
      };
    });

    safe(function () {
      Object.defineProperty(ms, 'metadata', {
        configurable: true,
        enumerable: true,
        get: function () {
          return state.metadata;
        },
        set: function (value) {
          state.metadata = value || null;
          // An ad's title, channel and picture never reach the phone's
          // controls (YouTube names the ad here while it plays). Only what
          // is set while the ad class is on counts, and never the video's
          // own (its title is the page's or one from the player data).
          state.metadataIsAd = adClassOnPlayer() && !isContentMeta(value);
          if (metaDesc && metaDesc.set && !state.metadataIsAd) {
            try {
              metaDesc.set.call(ms, value);
            } catch (e) {
              // a plain object instead of a real MediaMetadata: keep our copy only
            }
          }
          schedulePost('metadata');
        },
      });
    });

    if (typeof ms.setPositionState !== 'function') {
      safe(function () {
        ms.setPositionState = function () {};
      });
    }
  }
  installMediaSession();

  // ---------------------------------------------------------------------------
  // (c) The main video and the messages to Dart.
  // ---------------------------------------------------------------------------
  function isVideo(el) {
    return !!el && typeof el === 'object' && String(el.tagName || '').toUpperCase() === 'VIDEO';
  }

  function findVideo() {
    if (isVideo(state.video) && state.video.isConnected !== false) return state.video;
    return safe(function () {
      return (
        doc.querySelector('video.html5-main-video') ||
        doc.querySelector('#movie_player video') ||
        doc.querySelector('#player video') ||
        doc.querySelector('video')
      );
    }, null);
  }

  function findNextButton() {
    return safe(function () {
      return (
        doc.querySelector('.ytp-next-button') ||
        doc.querySelector('button[aria-label="Next video"]') ||
        doc.querySelector('[aria-label="Next video"]') ||
        doc.querySelector('.player-controls-middle-core-buttons button:last-child')
      );
    }, null);
  }

  function text(v, max) {
    if (v === undefined || v === null) return '';
    var s = String(v).replace(/\s+/g, ' ').trim();
    return s.length > max ? s.substring(0, max) : s;
  }

  function pageTitle() {
    var t = text(doc.title, 300);
    return t.replace(/ - YouTube$/, '');
  }

  function channelName() {
    return safe(function () {
      var el =
        doc.querySelector('.slim-owner-channel-name') ||
        doc.querySelector('ytm-slim-owner-renderer .slim-owner-channel-name') ||
        doc.querySelector('.ytd-channel-name a') ||
        doc.querySelector('[itemprop="author"] [itemprop="name"]');
      if (!el) return '';
      return text(el.textContent || el.getAttribute('content'), 160);
    }, '');
  }

  function artworkUrl(meta) {
    return safe(function () {
      var list = meta && meta.artwork;
      if (!list || !list.length) return '';
      var best = null;
      var bestSize = -1;
      for (var i = 0; i < list.length; i++) {
        var a = list[i] || {};
        var size = parseInt(String(a.sizes || '0').split('x')[0], 10) || 0;
        if (a.src && size >= bestSize) {
          best = a.src;
          bestSize = size;
        }
      }
      return best ? text(best, 2048) : '';
    }, '');
  }

  function status(v) {
    if (!v || v.muted) return 'none'; // no sound: nothing for the notification
    if (v.isConnected === false) return 'none';
    if (v.ended) return 'ended';
    if (v.paused) return 'paused';
    if (v.readyState !== undefined && v.readyState < 3 && !v.seeking) return 'buffering';
    return 'playing';
  }

  function num(v) {
    return typeof v === 'number' && isFinite(v) ? Math.round(v * 1000) / 1000 : null;
  }

  // For a pause of the main video: [pausedByPage, pausedFromSystemControls].
  function pauseCause(eventType, v) {
    if (eventType !== 'pause' || !v || !v.paused) return [false, false];
    var t = now();
    var native = !!(state.nativeAt.pause && t - state.nativeAt.pause < 1500) ||
      !!(state.nativeAt.stop && t - state.nativeAt.stop < 1500);
    // The page's script paused this very video (a muted feed preview it
    // paused a moment before does not count).
    var byScript = state.scriptPauseEl === v && state.scriptPauseAt > 0 && t - state.scriptPauseAt < 1000;
    var userTouched = state.lastInputAt > 0 && state.scriptPauseAt - state.lastInputAt < INPUT_GRACE_MS;
    return [byScript && !native && !userTouched, native];
  }

  // While an ad is being skipped (Block ads on), the phone's controls keep
  // the video's own title, channel, picture, position and length, and show
  // it as loading: the ad's own never reach them. The event is always 'ad',
  // so Dart never takes the skip (the ad run to its end, its pause and seek)
  // for a pause or a seek of the video. A pause the viewer made during the
  // ad (a loaded ad, paused, not at its end) still shows as one.
  function adSnapshot(v) {
    var u = String(w.location && w.location.href ? w.location.href : '');
    var c = state.lastContent && state.lastContent.u === u ? state.lastContent : null;
    var paused = !!v && v.paused === true && !v.ended && !(v.readyState < 2);
    return {
      t: TOKEN,
      k: 'media',
      e: 'ad',
      u: u,
      s: paused ? 'paused' : 'buffering',
      p: c ? c.p : 0,
      d: c ? c.d : null,
      r: c ? c.r : 1,
      ti: c ? c.ti : text(pageTitle(), 300),
      ar: c ? c.ar : text(channelName(), 160),
      aw: c ? c.aw : '',
      n: !!state.handlers.nexttrack || !!findNextButton(),
      vw: c ? c.vw : 0,
      vh: c ? c.vh : 0,
      yp: false,
      na: false,
    };
  }

  function snapshot(eventType) {
    var v = findVideo();
    if (adShowing()) return adSnapshot(v);
    var meta = state.metadataIsAd ? null : state.metadata;
    var cause = pauseCause(eventType, v);
    var msg = {
      t: TOKEN,
      k: 'media',
      e: eventType || '',
      u: String(w.location && w.location.href ? w.location.href : ''),
      s: status(v),
      p: v ? num(v.currentTime) || 0 : 0,
      d: v ? num(v.duration) : null,
      r: v ? num(v.playbackRate) || 1 : 1,
      ti: text((meta && meta.title) || pageTitle(), 300),
      ar: text((meta && meta.artist) || channelName(), 160),
      aw: artworkUrl(meta),
      n: !!state.handlers.nexttrack || !!findNextButton(),
      vw: v ? v.videoWidth || 0 : 0,
      vh: v ? v.videoHeight || 0 : 0,
      // Why a 'pause' happened: the page paused itself (no user input, not
      // us), or the phone's own media controls (lock screen) paused it.
      yp: cause[0],
      na: cause[1],
    };
    state.lastContent = msg;
    if (cause[0]) {
      state.idlePauseAt = now();
      // YouTube's "Continue watching?" prompt shows up with such a pause.
      safe(function () {
        w.setTimeout(confirmStillWatching, 800);
      });
    }
    return msg;
  }

  function send(msg) {
    // Only the reference captured at injection (or when the platform said it
    // is ready): a later wrapper put in place by a page script never runs.
    if (!platform) return false;
    try {
      var r = invoke(platform.call, platform.obj, [HANDLER, msg]);
      if (r && typeof r.catch === 'function') r.catch(function () {});
      return true;
    } catch (e) {
      return false;
    }
  }

  function post(msg) {
    if (!send(msg)) state.pending = msg; // flushed when the platform bridge is ready
  }

  function postMedia(eventType) {
    safe(function () {
      var msg = snapshot(eventType);
      var key = [msg.s, msg.u, msg.ti, msg.ar, msg.aw, msg.n, msg.d, msg.r, msg.vw, msg.vh].join('|');
      // Unchanged and not a tick: nothing to say.
      if (key === state.lastKey && eventType !== 'timeupdate' && eventType !== 'request' && eventType !== 'seeked') return;
      state.lastKey = key;
      post(msg);
    });
  }

  var scheduled = false;
  function schedulePost(eventType) {
    if (scheduled) return;
    scheduled = true;
    safe(function () {
      w.setTimeout(function () {
        scheduled = false;
        postMedia(eventType);
      }, 0);
    });
  }

  function onMediaEvent(event) {
    safe(function () {
      var el = event && event.target;
      if (!isVideo(el)) return;
      var type = event.type;
      // First, so an ad is muted and skipped before anything is reported.
      adOnMediaEvent(el);
      if (state.video && state.video.isConnected === false) state.video = null;
      // Muted feed previews (inline playback on the home page) never count.
      if (el.muted && el !== state.video) return;
      if (type === 'play' || type === 'playing' || type === 'loadedmetadata') {
        if (!el.muted) state.video = el;
        if ('autoPictureInPicture' in el) el.autoPictureInPicture = !!state.autoPip;
        if (state.pipLayout) markPipVideo(true);
      } else if (state.video && el !== state.video) {
        return; // another video changed: ignore
      }
      if (type === 'timeupdate') {
        var t = now();
        if (t - state.lastTick < TICK_MS) return;
        state.lastTick = t;
      }
      postMedia(type);
    });
  }

  ['play', 'playing', 'pause', 'ended', 'loadedmetadata', 'ratechange', 'durationchange', 'timeupdate', 'seeked', 'waiting', 'emptied'].forEach(
    function (type) {
      safe(function () {
        doc.addEventListener(type, onMediaEvent, true);
      });
    }
  );

  // Fullscreen, as the page sees it: an element holding a video is the
  // page's fullscreen element, or a video plays in iOS's native fullscreen
  // player. Dart trusts this on iOS, where the plugin's own fullscreen event
  // also fires for app windows that have nothing to do with the page.
  function holdsVideo(el) {
    if (!el) return false;
    if (isVideo(el)) return true;
    var v = findVideo();
    for (var p = v; p; p = p.parentElement) {
      if (p === el) return true;
    }
    return !!(typeof el.querySelector === 'function' && el.querySelector('video'));
  }

  function elementFullscreen() {
    return safe(function () {
      return holdsVideo(doc.fullscreenElement || doc.webkitFullscreenElement || doc.webkitCurrentFullScreenElement || null);
    }, false);
  }

  function nativeVideoFullscreen(v) {
    return !!v && (v.webkitDisplayingFullscreen === true || v.webkitPresentationMode === 'fullscreen');
  }

  var lastFullscreen = false;
  function postFullscreen(on) {
    if (on === lastFullscreen) return;
    lastFullscreen = on;
    post({ t: TOKEN, k: 'fs', on: on, u: String(w.location.href) });
  }

  function onFullscreenEvent(event) {
    safe(function () {
      var type = event && event.type;
      var el = event && event.target;
      var on;
      if (type === 'webkitbeginfullscreen' || type === 'webkitendfullscreen') {
        if (!isVideo(el)) return;
        // The video's own flag may still be the old one while the event runs.
        on = type === 'webkitbeginfullscreen' || elementFullscreen();
      } else {
        on = elementFullscreen() || nativeVideoFullscreen(findVideo());
      }
      postFullscreen(!!on);
    });
  }
  ['fullscreenchange', 'webkitfullscreenchange', 'webkitbeginfullscreen', 'webkitendfullscreen'].forEach(function (type) {
    safe(function () {
      doc.addEventListener(type, onFullscreenEvent, true);
    });
  });

  function onPresentationChange(event) {
    safe(function () {
      var el = event && event.target;
      if (!isVideo(el)) return;
      var mode = el.webkitPresentationMode;
      var on = event.type === 'enterpictureinpicture' || mode === 'picture-in-picture';
      post({ t: TOKEN, k: 'pip', on: !!on, u: String(w.location.href) });
      if (event.type === 'webkitpresentationmodechanged') {
        postFullscreen(mode === 'fullscreen' || elementFullscreen());
      }
    });
  }
  ['webkitpresentationmodechanged', 'enterpictureinpicture', 'leavepictureinpicture'].forEach(function (type) {
    safe(function () {
      doc.addEventListener(type, onPresentationChange, true);
    });
  });

  // "ready" is said once per document, as soon as it can be: Dart takes it to
  // mean a new document replaced the old one (and the old video with it).
  var readyPosted = false;
  function postReady() {
    if (readyPosted) return;
    readyPosted = true;
    post({ t: TOKEN, k: 'ready', u: String(w.location.href) });
  }

  safe(function () {
    w.addEventListener('flutterInAppWebViewPlatformReady', function () {
      capturePlatform(); // the platform object arrived after injection (older WebViews)
      state.ready = true;
      var p = state.pending;
      state.pending = null;
      postReady();
      if (p) post(p);
    });
  });

  // ---------------------------------------------------------------------------
  // (d) Commands from Dart.
  // ---------------------------------------------------------------------------
  function callHandler(action, details) {
    var h = state.handlers[action];
    if (typeof h !== 'function') return false;
    var t = now();
    if (state.nativeAt[action] && t - state.nativeAt[action] < DEDUPE_MS) return true; // already done by the browser
    state.bridgeAt[action] = t;
    try {
      h(details || { action: action });
    } catch (e) {
      return false;
    }
    return true;
  }

  function play() {
    var v = findVideo();
    if (!v) return callHandler('play');
    // YouTube starts a page opened without a tap muted (its own autoplay
    // rule). A play from MediaHub is the user's: with sound. An ad muted by
    // the ad blocker is left as it is.
    if (v.muted && !(ad.active && ad.active.video === v && ad.active.mutedByUs)) {
      safe(function () {
        v.muted = false;
      });
      safe(function () {
        var p = playerOf(v) || doc.getElementById('movie_player');
        if (p && typeof p.unMute === 'function') p.unMute();
      });
    }
    try {
      var r = v.play();
      if (r && typeof r.catch === 'function') r.catch(function () {});
    } catch (e) {
      return false;
    }
    return true;
  }

  function pause() {
    var v = findVideo();
    // Our own pause is never mistaken for one the page made by itself.
    state.bridgePausing = true;
    try {
      if (!v) return callHandler('pause');
      v.pause();
    } catch (e) {
      return false;
    } finally {
      state.bridgePausing = false;
    }
    return true;
  }

  function seekTo(seconds) {
    var v = findVideo();
    if (!v || typeof seconds !== 'number' || !isFinite(seconds)) return false;
    var s = Math.max(0, seconds);
    if (typeof v.duration === 'number' && isFinite(v.duration)) s = Math.min(s, v.duration);
    if (state.handlers.seekto && callHandler('seekto', { action: 'seekto', seekTime: s })) return true;
    try {
      v.currentTime = s;
    } catch (e) {
      return false;
    }
    return true;
  }

  function next() {
    if (callHandler('nexttrack')) return true;
    var b = findNextButton();
    if (b && typeof b.click === 'function') {
      try {
        b.click();
        return true;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  function restart(v) {
    if (!v) return false;
    try {
      v.currentTime = 0;
      return true;
    } catch (e) {
      return false;
    }
  }

  function previous() {
    var v = findVideo();
    // Like the music player: past 3 s, "previous" restarts the video.
    if (v && typeof v.currentTime === 'number' && v.currentTime > 3) return restart(v);
    if (callHandler('previoustrack')) return true;
    // Never the browser's history: the lock screen must not walk the user
    // back through the pages they browsed. Without a page handler it restarts.
    return restart(v);
  }

  // Leaves the page's fullscreen (system Back while a video is fullscreen).
  function exitFullscreen() {
    return safe(function () {
      if (doc.fullscreenElement && typeof doc.exitFullscreen === 'function') {
        var r = doc.exitFullscreen();
        if (r && typeof r.catch === 'function') r.catch(function () {});
        return true;
      }
      if (doc.webkitFullscreenElement && typeof doc.webkitExitFullscreen === 'function') {
        doc.webkitExitFullscreen();
        return true;
      }
      var v = findVideo();
      if (v && v.webkitDisplayingFullscreen && typeof v.webkitExitFullscreen === 'function') {
        v.webkitExitFullscreen(); // iOS native video fullscreen
        return true;
      }
      return false;
    }, false);
  }

  // The form's own submit button (a <button> with no type is one too), by
  // structure only, never by its label.
  function submitButton(form) {
    return safe(function () {
      if (typeof form.querySelectorAll !== 'function') return null;
      var list = form.querySelectorAll('button, input[type="submit"]');
      for (var i = 0; i < list.length; i++) {
        var b = list[i];
        if (b && String(b.type || '').toLowerCase() === 'submit' && !b.disabled && typeof b.click === 'function') return b;
      }
      return null;
    }, null);
  }

  // Our own search box's query, submitted inside YouTube's single-page app
  // (so its mini player keeps playing). Only structural selectors: the
  // search field's name and YouTube's own element names, never a label in
  // one language. False when the page has no search field to use, or no way
  // to submit it that is sure to work; Dart then loads the results page
  // itself.
  function search(query) {
    if (typeof query !== 'string') return false;
    var q = query.replace(/\s+/g, ' ').trim();
    if (!q || q.length > MAX_QUERY) return false;
    return safe(function () {
      var input =
        doc.querySelector('input[name="search_query"]') ||
        doc.querySelector('ytm-searchbox input') ||
        doc.querySelector('input.searchbox-input') ||
        doc.querySelector('input[name="search"]') ||
        doc.querySelector('ytmusic-search-box input') ||
        doc.querySelector('form[action="/results"] input');
      if (!input) return false;
      var proto = w.HTMLInputElement && w.HTMLInputElement.prototype;
      var desc = proto ? Object.getOwnPropertyDescriptor(proto, 'value') : null;
      if (desc && typeof desc.set === 'function') desc.set.call(input, q);
      else input.value = q;
      safe(function () {
        input.dispatchEvent(new w.Event('input', { bubbles: true }));
      });
      var form = input.form || null;
      if (form && typeof form.requestSubmit === 'function') {
        form.requestSubmit(); // the app's own submit handler runs (no page load)
        return true;
      }
      if (form) {
        // No requestSubmit (iOS 15's WebKit). A scripted Enter key never
        // submits a form, so it is not tried here: a click on the form's
        // submit button does submit it (the app's handler runs, as above).
        // Without one, false: Dart loads the results page, which is what
        // form.submit() would do, but at an address known to be right.
        var button = submitButton(form);
        if (!button) return false;
        button.click();
        return true;
      }
      if (typeof w.KeyboardEvent === 'function') {
        var init = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
        input.dispatchEvent(new w.KeyboardEvent('keydown', init));
        input.dispatchEvent(new w.KeyboardEvent('keyup', init));
        return true;
      }
      return false;
    }, false);
  }

  // ---------------------------------------------------------------------------
  // (e) Picture-in-picture.
  // ---------------------------------------------------------------------------
  var styleInstalled = false;
  function installPipStyle() {
    if (styleInstalled) return;
    styleInstalled = safe(function () {
      var css =
        'html.' + PIP_CLASS + ',html.' + PIP_CLASS + ' body{overflow:hidden!important;background:#000!important}' +
        'html.' + PIP_CLASS + ' .' + PIP_ANCESTOR_CLASS +
        '{transform:none!important;filter:none!important;contain:none!important;overflow:visible!important;' +
        'will-change:auto!important;clip-path:none!important}' +
        'html.' + PIP_CLASS + ' video.' + PIP_VIDEO_CLASS +
        '{position:fixed!important;inset:0!important;top:0!important;left:0!important;width:100vw!important;' +
        'height:100vh!important;max-width:none!important;max-height:none!important;margin:0!important;' +
        'object-fit:contain!important;background:#000!important;z-index:2147483647!important;transform:none!important}' +
        // Only the video shows in the floating window: YouTube's top bar, its
        // "Next" banner and the player controls stack above even the highest
        // z-index, so everything else is hidden (still laid out, so the page
        // and its player carry on as before).
        'html.' + PIP_CLASS + ' *{visibility:hidden!important}' +
        'html.' + PIP_CLASS + ' video.' + PIP_VIDEO_CLASS + '{visibility:visible!important}' +
        // Captions (when the viewer turned them on) stay: they are part of the video.
        'html.' + PIP_CLASS + ' .ytp-caption-window-container,html.' + PIP_CLASS +
        ' .ytp-caption-window-container *{visibility:visible!important}';
      var el = doc.createElement('style');
      el.setAttribute('data-mediahub', 'pip');
      el.textContent = css;
      (doc.head || doc.documentElement).appendChild(el);
      return true;
    }, false);
  }

  function markPipVideo(on) {
    safe(function () {
      var old = doc.querySelectorAll('.' + PIP_VIDEO_CLASS + ',.' + PIP_ANCESTOR_CLASS);
      for (var i = 0; i < old.length; i++) {
        old[i].classList.remove(PIP_VIDEO_CLASS);
        old[i].classList.remove(PIP_ANCESTOR_CLASS);
      }
      if (!on) return;
      var v = findVideo();
      if (!v) return;
      v.classList.add(PIP_VIDEO_CLASS);
      var p = v.parentElement;
      while (p && p !== doc.body && p !== doc.documentElement) {
        p.classList.add(PIP_ANCESTOR_CLASS);
        p = p.parentElement;
      }
    });
  }

  function setPipLayout(on) {
    state.pipLayout = !!on;
    if (state.pipLayout) installPipStyle();
    safe(function () {
      var root = doc.documentElement;
      if (state.pipLayout) root.classList.add(PIP_CLASS);
      else root.classList.remove(PIP_CLASS);
    });
    markPipVideo(state.pipLayout);
    return true;
  }

  function enterPip() {
    var v = findVideo();
    if (!v) return false;
    try {
      if (typeof v.webkitSupportsPresentationMode === 'function' && v.webkitSupportsPresentationMode('picture-in-picture')) {
        v.webkitSetPresentationMode('picture-in-picture');
        return true;
      }
      if (typeof v.requestPictureInPicture === 'function') {
        var r = v.requestPictureInPicture();
        if (r && typeof r.catch === 'function') r.catch(function () {});
        return true;
      }
    } catch (e) {
      return false;
    }
    return false;
  }

  function setAutoPip(on) {
    state.autoPip = !!on;
    var v = findVideo();
    if (v && 'autoPictureInPicture' in v) {
      safe(function () {
        v.autoPictureInPicture = state.autoPip;
      });
    }
    return true;
  }

  // Back to the page from the browser's own picture-in-picture (iOS): used
  // when it was started by a short trip to Control Center that never left
  // the app.
  function exitPip() {
    var v = findVideo();
    try {
      if (v && typeof v.webkitSetPresentationMode === 'function' && v.webkitPresentationMode === 'picture-in-picture') {
        v.webkitSetPresentationMode('inline');
        return true;
      }
      if (doc.pictureInPictureElement && typeof doc.exitPictureInPicture === 'function') {
        var r = doc.exitPictureInPicture();
        if (r && typeof r.catch === 'function') r.catch(function () {});
        return true;
      }
    } catch (e) {
      return false;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // (f) Keep-alive while "Background play" is on.
  // ---------------------------------------------------------------------------
  // YouTube's prompts that stop a long listen ("Video paused. Continue
  // watching?", YouTube Music's "Still there?"), by element name. Only ever
  // pressed after the page paused the main video by itself with no touch or
  // key from the user since, so a dialog the user opened is never confirmed.
  var STILL_WATCHING = [
    'yt-confirm-dialog-renderer #confirm-button button',
    'yt-confirm-dialog-renderer #confirm-button',
    'ytmusic-you-there-renderer button',
    'ytm-you-there-renderer button',
  ];

  function confirmStillWatching() {
    return safe(function () {
      if (!state.background || !state.idlePauseAt) return false;
      if (state.lastInputAt > state.idlePauseAt) {
        state.idlePauseAt = 0; // the user has been back since: theirs to answer
        return false;
      }
      var v = findVideo();
      if (!v || !v.paused || v.ended) return false;
      for (var i = 0; i < STILL_WATCHING.length; i++) {
        var b = doc.querySelector(STILL_WATCHING[i]);
        if (b && typeof b.click === 'function') {
          b.click();
          state.idlePauseAt = 0;
          play();
          return true;
        }
      }
      return false;
    }, false);
  }

  function keepAlive() {
    if (!state.background) return;
    // YouTube's last-activity clock: an hour without "activity" is what
    // brings up its "Continue watching?" stop.
    safe(function () {
      w._lact = now();
    });
    confirmStillWatching();
  }
  safe(function () {
    w.setInterval(keepAlive, KEEPALIVE_MS);
  });

  // ---------------------------------------------------------------------------
  // (g) Ad blocking (Settings → Online → Block ads, on by default).
  // ---------------------------------------------------------------------------
  // Four layers, none of them a timer or a scan of the page:
  //  1. YouTube's player data loses its ad fields before the player reads it,
  //     the way uBlock Origin's json-prune does: JSON.parse, Response json()
  //     and text() for the player and next endpoints, and the page's own
  //     ytInitialPlayerResponse / ytInitialData. Only those keys go; nothing
  //     else in the JSON changes, and a parse error reaches the page as before.
  //  2. An ad that still plays (the player has the ad-showing class) is
  //     muted and its Skip button pressed; the sound comes back after. It is
  //     run to its end only when it is surely a short mid-roll ad (see
  //     adMediaKind): never on a doubt, so the video itself is never skipped.
  //     A pre-roll, an ad stitched into the video's stream and anything
  //     around the next video are only muted and skipped.
  //     A MutationObserver on the player's class (that one element) and the
  //     video's own events start it.
  //  3. Ad boxes in the feed, in search and under the player are hidden by a
  //     style sheet.
  //  4. The page's requests to ad and ad-tracking addresses (fetch, XHR,
  //     sendBeacon) fail like a blocked request. Never the video itself
  //     (googlevideo.com), YouTube's player API or its pictures.
  // YouTube's "Ad blockers are not allowed" message is pruned from the same
  // data (enforcementMessageViewModel) and hidden if it shows anyway.
  var AD_KEYS = ['adPlacements', 'playerAds', 'adSlots'];
  var ENFORCEMENT_KEYS = ['enforcementMessageViewModel', 'bkaEnforcementMessageViewModel'];
  var AD_TEXT = /"(?:adPlacements|playerAds|adSlots|enforcementMessageViewModel|bkaEnforcementMessageViewModel)"/;
  var PLAYER_API = /\/youtubei\/v1\/(?:player|next|get_watch)(?:[?#\/]|$)/;
  var AD_SKIP_BUTTONS = [
    '.ytp-ad-skip-button-modern',
    '.ytp-ad-skip-button',
    '.ytp-skip-ad-button',
    '.ytp-ad-skip-button-slot button',
  ];
  // m.youtube.com first, then www.youtube.com (an iPad, a desktop-class page).
  var AD_SELECTORS = [
    'ytm-promoted-sparkles-web-renderer',
    'ytm-promoted-sparkles-text-search-renderer',
    'ytm-promoted-video-renderer',
    'ytm-companion-ad-renderer',
    'ytm-companion-slot',
    'ad-slot-renderer',
    'ytm-ad-slot-renderer',
    'ytm-statement-banner-renderer',
    'ytm-engagement-panel-section-list-renderer[target-id="engagement-panel-ads"]',
    'ytm-enforcement-message-view-model',
    'ytd-ad-slot-renderer',
    'ytd-in-feed-ad-layout-renderer',
    'ytd-promoted-sparkles-web-renderer',
    'ytd-promoted-video-renderer',
    'ytd-display-ad-renderer',
    'ytd-companion-slot-renderer',
    'ytd-action-companion-ad-renderer',
    'ytd-player-legacy-desktop-watch-ads-renderer',
    'ytd-banner-promo-renderer',
    'ytd-statement-banner-renderer',
    'ytd-search-pyv-renderer',
    'ytd-engagement-panel-section-list-renderer[target-id="engagement-panel-ads"]',
    'ytd-enforcement-message-view-model',
    '#masthead-ad',
    '#player-ads',
    '.ytp-ad-overlay-container',
    '.ytp-ad-overlay-slot',
  ];
  // The boxes around an ad. Each :has() rule stands alone: a browser without
  // :has() drops that one rule, not the whole list above.
  var AD_HAS_SELECTORS = [
    'ytm-rich-item-renderer:has(> ad-slot-renderer)',
    'ytm-rich-item-renderer:has(> ytm-ad-slot-renderer)',
    'ytd-rich-item-renderer:has(ytd-ad-slot-renderer)',
    'tp-yt-paper-dialog:has(ytd-enforcement-message-view-model)',
    'body:has(ytd-enforcement-message-view-model) tp-yt-iron-overlay-backdrop',
  ];
  // Ad and ad-tracking addresses: a cheap first look at every request, then
  // the host (ad networks) or YouTube's own ad paths.
  var AD_REQUEST_HINT = /doubleclick|googlead|googlesyndication|googletagservices|imasdk|\/pagead\/|\/api\/stats\/ads|\/ptracking|\/get_midroll_/i;
  var AD_HOST = /(?:^|\.)(?:doubleclick\.net|googleadservices\.com|googlesyndication\.com|googletagservices\.com|imasdk\.googleapis\.com)$/;
  var AD_YOUTUBE_PATH = /^\/(?:pagead\/|api\/stats\/ads|ptracking|get_midroll_)/;
  // Seconds between a media element's length and videoDetails.lengthSeconds
  // (whole seconds) that still count as the same length.
  var LENGTH_SLACK = 1.5;
  // Only an ad this short is ever run to its end. An ad YouTube does not let
  // the viewer skip is 30 s at most; a longer one has a Skip button, which
  // is pressed instead.
  var AD_SEEK_MAX = 31.5;
  // The video counts as seen playing only this far (seconds) before its end:
  // after that the next video may be about to load.
  var CONTENT_END_MARGIN = 5;
  var hasOwn = Object.prototype.hasOwnProperty;
  var nativeParse = JSON.parse;
  var nativeStringify = JSON.stringify;
  var ProxyCtor = typeof Proxy === 'function' ? Proxy : null;
  var adCounts = { pruned: 0, adBreaks: 0, blocked: 0 };
  // The player whose class is watched, its observer, the ad being skipped:
  // { video, muted (before us), mutedByUs, src (the break's first stream,
  // the only one that may be run to its end) }, and the address's own video
  // last seen playing in the player's element with the ad class off:
  // { video, src, id, len } or null (see seeContent).
  var ad = { player: null, observer: null, active: null, content: null };
  // The videos' own length and title (videoDetails) by video id, from the
  // player data seen (the last 20 videos): { byId: { id: { len, title } },
  // ids, last (the id of the player data seen last) }.
  var content = { byId: {}, ids: [], last: '' };

  function isObject(v) {
    return !!v && typeof v === 'object';
  }

  // A page function swapped for a wrapper that still looks native to the
  // page (its toString stays "[native code]"): a Proxy where there is one.
  function wrapFunction(original, apply) {
    if (ProxyCtor) {
      return new ProxyCtor(original, {
        apply: function (target, self, args) {
          return apply(target, self, args);
        },
      });
    }
    return function () {
      return apply(original, this, Array.prototype.slice.call(arguments));
    };
  }

  function dropKeys(o, keys) {
    var n = 0;
    for (var i = 0; i < keys.length; i++) {
      if (hasOwn.call(o, keys[i]) && delete o[keys[i]]) n++;
    }
    return n;
  }

  // Marks of an answer from YouTube's own API: only such objects lose
  // top-level ad keys, so other JSON on the page is never touched.
  function looksLikePlayerData(o) {
    return (
      hasOwn.call(o, 'responseContext') ||
      hasOwn.call(o, 'playabilityStatus') ||
      hasOwn.call(o, 'videoDetails') ||
      hasOwn.call(o, 'streamingData')
    );
  }

  function dropEnforcement(o) {
    var aux = o.auxiliaryUi;
    var renderers = isObject(aux) ? aux.messageRenderers : null;
    return isObject(renderers) ? dropKeys(renderers, ENFORCEMENT_KEYS) : 0;
  }

  function noteContent(o) {
    var vd = o.videoDetails;
    if (!isObject(vd)) return;
    var id = vd.videoId;
    if (typeof id !== 'string' || !id) return;
    var len = Number(vd.lengthSeconds);
    var title = text(vd.title, 300);
    var old = hasOwn.call(content.byId, id) ? content.byId[id] : null;
    if (!old) {
      content.ids.push(id);
      if (content.ids.length > 20) delete content.byId[content.ids.shift()];
    }
    content.byId[id] = { len: len > 0 ? len : old ? old.len : 0, title: title || (old ? old.title : '') };
    content.last = id;
  }

  function prunePlayer(o) {
    noteContent(o);
    return dropKeys(o, AD_KEYS) + dropEnforcement(o);
  }

  function pruneOne(o) {
    if (!isObject(o) || Array.isArray(o)) return 0;
    var n = looksLikePlayerData(o) ? prunePlayer(o) : 0;
    var pr = o.playerResponse;
    if (isObject(pr) && !Array.isArray(pr)) n += prunePlayer(pr);
    return n;
  }

  // Removes the ad fields from YouTube's player data, in place. Returns how
  // many went.
  function pruneAds(value) {
    if (!BLOCK_ADS || !isObject(value)) return 0;
    var n = 0;
    if (Array.isArray(value)) {
      // Older watch answers are a short list of parts, one the player's.
      for (var i = 0; i < value.length && i < 8; i++) n += pruneOne(value[i]);
    } else {
      n = pruneOne(value);
    }
    if (n) adCounts.pruned += n;
    return n;
  }

  // A player API answer read as text: the same keys go, the rest of the text
  // stays exactly as it came when there was nothing to remove.
  function pruneText(body) {
    if (typeof body !== 'string' || !AD_TEXT.test(body)) return body;
    var guard = /^\)\]\}'\s*/.exec(body); // YouTube's anti-JSON-hijacking prefix
    var prefix = guard ? guard[0] : '';
    var data = invoke(nativeParse, JSON, [body.substring(prefix.length)]);
    if (!pruneAds(data)) return body;
    return prefix + invoke(nativeStringify, JSON, [data]);
  }

  function hookJsonParse() {
    if (typeof nativeParse !== 'function') return;
    JSON.parse = wrapFunction(nativeParse, function (target, self, args) {
      var result = invoke(target, self, args); // a SyntaxError still reaches the page
      safe(function () {
        pruneAds(result);
      });
      return result;
    });
  }

  function isPlayerApi(response) {
    var url = safe(function () {
      return response.url;
    }, '');
    return typeof url === 'string' && PLAYER_API.test(url);
  }

  function hookResponses() {
    var R = w.Response;
    var proto = R && R.prototype;
    if (!proto) return;
    var json = proto.json;
    if (typeof json === 'function') {
      proto.json = wrapFunction(json, function (target, self, args) {
        var p = invoke(target, self, args);
        if (!p || typeof p.then !== 'function' || !isPlayerApi(self)) return p;
        return p.then(function (data) {
          safe(function () {
            pruneAds(data);
          });
          return data;
        });
      });
    }
    var textFn = proto.text;
    if (typeof textFn === 'function') {
      proto.text = wrapFunction(textFn, function (target, self, args) {
        var p = invoke(target, self, args);
        if (!p || typeof p.then !== 'function' || !isPlayerApi(self)) return p;
        return p.then(function (body) {
          return safe(function () {
            return pruneText(body);
          }, body);
        });
      });
    }
  }

  // window.ytInitialPlayerResponse / ytInitialData, set by the page's inline
  // scripts (a global `var` assignment goes through this setter too).
  function trapGlobal(name) {
    var desc = Object.getOwnPropertyDescriptor(w, name);
    if (desc && !desc.configurable) return;
    var value = desc ? (desc.get ? safe(function () { return desc.get.call(w); }) : desc.value) : undefined;
    safe(function () {
      pruneAds(value);
    });
    Object.defineProperty(w, name, {
      configurable: true,
      enumerable: true,
      get: function () {
        return value;
      },
      set: function (v) {
        safe(function () {
          pruneAds(v);
        });
        value = v;
      },
    });
  }

  // --- 2. An ad that plays anyway --------------------------------------------
  function playerOf(v) {
    if (v && typeof v.closest === 'function') {
      var found = safe(function () {
        return v.closest('.html5-video-player');
      }, null);
      if (found) return found;
    }
    for (var el = v ? v.parentElement : null; el; el = el.parentElement) {
      if (el.classList && el.classList.contains('html5-video-player')) return el;
    }
    return null;
  }

  // Metadata that names a video rather than an ad: its title is the page's
  // (YouTube Music's page title ends in " - YouTube Music") or the title of
  // a video in the player data seen.
  function isContentMeta(meta) {
    return safe(function () {
      var t = text(meta && meta.title, 300);
      if (!t) return false;
      var page = pageTitle();
      if (t === page || t === page.replace(/ - YouTube Music$/, '')) return true;
      for (var i = 0; i < content.ids.length; i++) {
        var c = content.byId[content.ids[i]];
        if (c && c.title === t) return true;
      }
      return false;
    }, false);
  }

  function hasAdClass(player) {
    var c = player && player.classList;
    return !!c && (c.contains('ad-showing') || c.contains('ad-interrupting'));
  }

  function adShowing() {
    if (!BLOCK_ADS) return false;
    var p = ad.player;
    return !!p && p.isConnected !== false && safe(function () { return hasAdClass(p); }, false);
  }

  // The ad class is on the main player, also before the player's first
  // media event (a pre-roll: YouTube names the ad as soon as its page starts).
  function adClassOnPlayer() {
    if (!BLOCK_ADS) return false;
    if (ad.player) return adShowing();
    return safe(function () {
      var v = findVideo();
      return hasAdClass(v ? playerOf(v) : null);
    }, false);
  }

  function watchPlayer(player) {
    if (!player || player === ad.player) return;
    ad.player = player;
    var MO = w.MutationObserver;
    if (typeof MO !== 'function') return; // the video's own events still do it
    safe(function () {
      if (ad.observer) ad.observer.disconnect();
      ad.observer = new MO(function () {
        safe(checkAd);
      });
      ad.observer.observe(player, { attributes: true, attributeFilter: ['class'] });
    });
  }

  function adVideo() {
    var p = ad.player;
    var v = p && typeof p.querySelector === 'function' ? safe(function () { return p.querySelector('video'); }, null) : null;
    return isVideo(v) ? v : findVideo();
  }

  function pageVideoId() {
    return safe(function () {
      var href = String(w.location.href || '');
      var m = /[?&]v=([\w-]{11})/.exec(href) || /\/(?:shorts|live)\/([\w-]{11})/.exec(href);
      return m ? m[1] : '';
    }, '');
  }

  function sameLength(a, b) {
    return Math.abs(a - b) < LENGTH_SLACK;
  }

  // The length of the video the address names, or 0 when the address names
  // none (YouTube's mini player while browsing Home or Search, YouTube
  // Music's player bar) or its player data was not seen.
  function pageLength(id) {
    var c = id && hasOwn.call(content.byId, id) ? content.byId[id] : null;
    return c ? c.len : 0;
  }

  // As long as another video seen in the player data: the next video of
  // autoplay or a playlist, loading while the address still names the last.
  function otherVideoLength(d, id) {
    for (var i = 0; i < content.ids.length; i++) {
      var c = content.ids[i] !== id ? content.byId[content.ids[i]] : null;
      if (c && c.len > 0 && sameLength(d, c.len)) return true;
    }
    return false;
  }

  function mediaSrc(v) {
    return safe(function () {
      return String(v.currentSrc || v.src || '');
    }, '');
  }

  function knownNumber(n) {
    return typeof n === 'number' && isFinite(n);
  }

  // With the ad class off, on each of the player's events: is its element
  // playing the address's own video? Its length is that video's, it is not
  // at (or near) its end, its stream is known, and the player data seen last
  // is that video's (no next video has been loaded since). Anything else
  // (another stream, an ended video, a video whose data is not the latest)
  // forgets it, so only what was seen just before an ad class counts.
  function seeContent(v) {
    ad.content = safe(function () {
      if (!v || v.ended) return null;
      var id = pageVideoId();
      var len = pageLength(id);
      var d = v.duration;
      var t = v.currentTime;
      var src = mediaSrc(v);
      if (!len || id !== content.last || !src || !knownNumber(d) || !knownNumber(t)) return null;
      if (!sameLength(d, len) || !(t < d - CONTENT_END_MARGIN)) return null;
      return { video: v, src: src, id: id, len: len };
    }, null);
  }

  // What the player's media is while the ad class is on:
  //  'video': the address's own video (its length): the player keeps the ad
  //           class a moment while the video itself loads again;
  //  'ad':    surely a mid-roll ad: just before the class came on, this same
  //           element was seen playing the address's own video (seeContent);
  //           the address and the latest player data still name that video;
  //           and this is another stream, of a known length that is short
  //           (an ad nobody can skip), clearly shorter than the video's and
  //           not as long as another video seen;
  //  '':      anything else, not sure: no video in the address or no length
  //           for it, the length not known yet, a pre-roll or the next video
  //           (nothing showed the video playing in this element first: it
  //           ended, the address or the player data moved on), the video's
  //           own stream (an ad stitched into it), or a length like another
  //           video's.
  // Only an 'ad' is ever run to its end; a doubt is muted at most.
  function adMediaKind(v) {
    var d = v.duration;
    if (!knownNumber(d) || !(d > 0)) return '';
    var id = pageVideoId();
    var expected = pageLength(id);
    if (!expected) return '';
    if (sameLength(d, expected)) return 'video';
    var c = ad.content;
    if (!c || c.video !== v || c.id !== id || content.last !== id) return '';
    var src = mediaSrc(v);
    if (!src || src === c.src) return '';
    if (!(d <= AD_SEEK_MAX) || !(d < c.len - LENGTH_SLACK)) return '';
    return otherVideoLength(d, id) ? '' : 'ad';
  }

  function pressSkip() {
    var root = ad.player && typeof ad.player.querySelector === 'function' ? ad.player : doc;
    return safe(function () {
      for (var i = 0; i < AD_SKIP_BUTTONS.length; i++) {
        var b = root.querySelector(AD_SKIP_BUTTONS[i]);
        if (b && typeof b.click === 'function') {
          b.click();
          return true;
        }
      }
      return false;
    }, false);
  }

  function skipAd() {
    var v = adVideo();
    if (!v) return false;
    var kind = adMediaKind(v);
    var a = ad.active;
    if (kind === 'video') {
      if (a) unmuteAd(a); // the video itself under a lingering class: left as it is
      return false;
    }
    if (!a || a.video !== v) {
      if (a) unmuteAd(a);
      a = ad.active = { video: v, muted: !!v.muted, mutedByUs: false, src: '' };
      adCounts.adBreaks++;
    }
    safe(function () {
      if (!v.muted) {
        v.muted = true;
        a.mutedByUs = true;
      }
    });
    // The break's first stream, whatever it is (YouTube gives each stream
    // its own address): once the element loads another under the same
    // class (a second ad, the next video), that one is never run to its end.
    var src = mediaSrc(v);
    if (!a.src) a.src = src;
    if (kind === 'ad' && src === a.src) {
      safe(function () {
        var d = v.duration;
        if (!(v.currentTime >= d - 0.25)) v.currentTime = d; // its end
      });
    }
    pressSkip();
    return true;
  }

  // The sound comes back as it was before the ad.
  function unmuteAd(a) {
    safe(function () {
      if (a.mutedByUs && a.video.muted) a.video.muted = a.muted;
      a.mutedByUs = false;
    });
  }

  function endAd() {
    var a = ad.active;
    if (!a) return;
    ad.active = null;
    unmuteAd(a);
    postMedia('adend'); // the video itself, at once
  }

  function checkAd() {
    if (!BLOCK_ADS) return;
    if (adShowing()) {
      skipAd();
      return;
    }
    if (ad.active) endAd();
    seeContent(adVideo());
  }

  function adOnMediaEvent(el) {
    if (!BLOCK_ADS) return;
    var player = playerOf(el);
    // A muted feed preview's own player never takes the watch from the main one.
    if (player && (!ad.player || !el.muted || el === state.video)) watchPlayer(player);
    if (ad.player) checkAd();
  }

  // --- 3. Ad boxes -----------------------------------------------------------
  var adStyleInstalled = false;
  function installAdStyle() {
    if (adStyleInstalled) return true;
    var root = doc.documentElement || doc.head;
    if (!root) return false;
    adStyleInstalled = safe(function () {
      var css = AD_SELECTORS.join(',') + '{display:none!important}';
      for (var i = 0; i < AD_HAS_SELECTORS.length; i++) css += AD_HAS_SELECTORS[i] + '{display:none!important}';
      var el = doc.createElement('style');
      el.setAttribute('data-mediahub', 'ads');
      el.textContent = css;
      root.appendChild(el);
      return true;
    }, false);
    return adStyleInstalled;
  }

  // At document start the <html> element may not exist yet: the style goes
  // in the moment it does (one observer on the document's own children).
  function installAdStyleSoon() {
    if (installAdStyle()) return;
    var MO = w.MutationObserver;
    if (typeof MO === 'function') {
      safe(function () {
        var mo = new MO(function () {
          if (installAdStyle()) mo.disconnect();
        });
        mo.observe(doc, { childList: true });
      });
    }
    safe(function () {
      doc.addEventListener('DOMContentLoaded', installAdStyle, true);
    });
  }

  // --- 4. Ad requests --------------------------------------------------------
  function isAdRequest(url) {
    if (typeof url !== 'string' || !AD_REQUEST_HINT.test(url)) return false;
    var host;
    var path;
    var m = /^(?:https?:)?\/\/([^\/?#]*)([^?#]*)/i.exec(url);
    if (m) {
      host = m[1].substring(m[1].lastIndexOf('@') + 1).replace(/:\d*$/, '').toLowerCase();
      path = m[2] || '/';
    } else if (url.charAt(0) === '/') {
      host = String(w.location.hostname || '').toLowerCase();
      path = url.split(/[?#]/)[0];
    } else {
      return false;
    }
    if (AD_HOST.test(host)) return true;
    return /(?:^|\.)youtube\.com$/.test(host) && AD_YOUTUBE_PATH.test(path);
  }

  function requestUrl(input) {
    return safe(function () {
      if (typeof input === 'string') return input;
      if (!input) return '';
      if (typeof input.url === 'string') return input.url; // a Request
      return String(input); // a URL
    }, '');
  }

  function blocked(input) {
    var yes = safe(function () {
      return isAdRequest(requestUrl(input));
    }, false);
    if (yes) adCounts.blocked++;
    return yes;
  }

  // A blocked XHR ends the way a refused request does: an error, no answer.
  function failXhr(xhr) {
    safe(function () {
      Object.defineProperty(xhr, 'readyState', { configurable: true, value: 4 });
    });
    ['readystatechange', 'error', 'loadend'].forEach(function (type) {
      safe(function () {
        xhr.dispatchEvent(new w.Event(type));
      });
    });
  }

  function hookRequests() {
    if (typeof w.fetch === 'function') {
      w.fetch = wrapFunction(w.fetch, function (target, self, args) {
        if (blocked(args[0])) return Promise.reject(new TypeError('Failed to fetch'));
        return invoke(target, self, args);
      });
    }
    var navigatorObj = w.navigator;
    if (navigatorObj && typeof navigatorObj.sendBeacon === 'function') {
      safe(function () {
        navigatorObj.sendBeacon = wrapFunction(navigatorObj.sendBeacon, function (target, self, args) {
          if (blocked(args[0])) return true; // "queued": nothing is sent
          return invoke(target, self, args);
        });
      });
    }
    var X = w.XMLHttpRequest;
    var xproto = X && X.prototype;
    if (!xproto || typeof xproto.open !== 'function' || typeof xproto.send !== 'function') return;
    if (typeof WeakMap !== 'function') return;
    var blockedXhr = new WeakMap();
    xproto.open = wrapFunction(xproto.open, function (target, self, args) {
      safe(function () {
        if (hasOwn.call(self, 'readyState')) delete self.readyState; // reused after a blocked request
        if (blocked(args[1])) blockedXhr.set(self, true);
        else blockedXhr['delete'](self);
      });
      return invoke(target, self, args);
    });
    xproto.send = wrapFunction(xproto.send, function (target, self, args) {
      var isAd = safe(function () {
        return blockedXhr.get(self) === true;
      }, false);
      if (!isAd) return invoke(target, self, args);
      safe(function () {
        w.setTimeout(function () {
          failXhr(self);
        }, 0);
      });
      return undefined;
    });
  }

  if (BLOCK_ADS) {
    safe(hookJsonParse);
    safe(hookResponses);
    safe(function () {
      trapGlobal('ytInitialPlayerResponse');
    });
    safe(function () {
      trapGlobal('ytInitialData');
    });
    safe(hookRequests);
    installAdStyleSoon();
  }

  var COMMANDS = {
    play: play,
    pause: pause,
    seekTo: seekTo,
    next: next,
    previous: previous,
    setBackgroundPlay: function (on) {
      state.background = !!on;
      return true;
    },
    setPipLayout: setPipLayout,
    enterPip: enterPip,
    setAutoPip: setAutoPip,
    exitPip: exitPip,
    exitFullscreen: exitFullscreen,
    search: search,
    requestState: function () {
      postMedia('request');
      return true;
    },
  };

  safe(function () {
    Object.defineProperty(w, '__mediahubBridge', {
      configurable: false,
      enumerable: false,
      writable: false,
      value: Object.freeze({
        version: 1,
        command: function (name, arg) {
          var fn = Object.prototype.hasOwnProperty.call(COMMANDS, name) ? COMMANDS[name] : null;
          if (!fn) return false;
          try {
            return !!fn(arg);
          } catch (e) {
            return false;
          }
        },
        // For the Node test only: whether the page currently looks hidden underneath.
        reallyHidden: reallyHidden,
        // For checks by hand (the WebView's inspector in debug builds): what
        // Block ads has done in this document so far.
        adStats: function () {
          return { on: BLOCK_ADS, pruned: adCounts.pruned, adBreaks: adCounts.adBreaks, blocked: adCounts.blocked };
        },
      }),
    });
  });

  // The platform bridge may already be up (scripts injected after load).
  if (platform) {
    state.ready = true;
    postReady();
  }
})();
