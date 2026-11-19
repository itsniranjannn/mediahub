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
//      watching?" prompt is confirmed when it paused the video by itself.
//
// Every message carries the token Dart put in place of the placeholder below;
// Dart drops messages without it. Nothing here may ever throw into the page:
// YouTube's markup changes often, so every DOM lookup is optional.
// Tests: node test/js/youtube_bridge_test.js
(function () {
  'use strict';
  var TOKEN = '__MEDIAHUB_BRIDGE_TOKEN__';
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
    metadata: null,
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
          if (metaDesc && metaDesc.set) {
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

  function snapshot(eventType) {
    var v = findVideo();
    var meta = state.metadata;
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
        'object-fit:contain!important;background:#000!important;z-index:2147483647!important;transform:none!important}';
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
      }),
    });
  });

  // The platform bridge may already be up (scripts injected after load).
  if (platform) {
    state.ready = true;
    postReady();
  }
})();
