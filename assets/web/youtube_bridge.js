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
//      fill the window (Android PiP), and the browser's own PiP on iOS.
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
  // page never sees the token.
  try {
    var loc = w.location;
    var host = String(loc.hostname || '').toLowerCase();
    if (String(loc.protocol) !== 'https:' || !/(^|\.)youtube\.com$/.test(host)) return;
  } catch (e) {
    return;
  }
  if (w.__mediahubBridge) return; // already installed in this document
  var doc = w.document;
  if (!doc) return;

  function now() {
    return Date.now();
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

  function snapshot(eventType) {
    var v = findVideo();
    var meta = state.metadata;
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
    };
    return msg;
  }

  function send(msg) {
    var bridge = w.flutter_inappwebview;
    if (bridge && typeof bridge.callHandler === 'function') {
      try {
        var r = bridge.callHandler(HANDLER, msg);
        if (r && typeof r.catch === 'function') r.catch(function () {});
        return true;
      } catch (e) {
        return false;
      }
    }
    return false;
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

  function onPresentationChange(event) {
    safe(function () {
      var el = event && event.target;
      if (!isVideo(el)) return;
      var mode = el.webkitPresentationMode;
      var on = event.type === 'enterpictureinpicture' || mode === 'picture-in-picture';
      post({ t: TOKEN, k: 'pip', on: !!on, u: String(w.location.href) });
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
    if (!v) return callHandler('pause');
    try {
      v.pause();
    } catch (e) {
      return false;
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

  function previous() {
    var v = findVideo();
    // Like the music player: past 3 s, "previous" restarts the video.
    if (v && typeof v.currentTime === 'number' && v.currentTime > 3) {
      try {
        v.currentTime = 0;
        return true;
      } catch (e) {
        return false;
      }
    }
    if (callHandler('previoustrack')) return true;
    try {
      if (w.history && w.history.length > 1) {
        w.history.back();
        return true;
      }
    } catch (e) {
      return false;
    }
    if (v) {
      try {
        v.currentTime = 0;
      } catch (e) {
        return false;
      }
    }
    return !!v;
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

  function focusSearch() {
    return safe(function () {
      var input = doc.querySelector('input.searchbox-input, input[name="search"], input#search');
      if (input && typeof input.focus === 'function') {
        input.focus();
        return true;
      }
      var button =
        doc.querySelector('button[aria-label="Search YouTube"]') ||
        doc.querySelector('ytm-topbar-renderer button.topbar-menu-button-avatar-button') ||
        doc.querySelector('button[aria-label*="Search"]');
      if (button && typeof button.click === 'function') {
        button.click();
        return true;
      }
      return false;
    }, false);
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
    focusSearch: focusSearch,
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
  if (w.flutter_inappwebview && typeof w.flutter_inappwebview.callHandler === 'function') {
    state.ready = true;
    postReady();
  }
})();
