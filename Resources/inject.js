/*
 * Express YT Music - page bridge
 *
 * Runs in music.youtube.com at document-end. Two jobs:
 *   1. report player state to the app  (mediaSession first, DOM as fallback)
 *   2. expose window.__eym control functions for the app to evaluate
 *
 * Deliberately NOT here: user-agent spoofing, navigator.webdriver / plugins /
 * userAgentData faking, cookie access, or any network call of any kind.
 */
(function () {
  "use strict";

  if (window.__eymInjected) return;
  window.__eymInjected = true;

  var POLL_MS = 500;

  function send(payload) {
    try {
      window.webkit.messageHandlers.eymBridge.postMessage(payload);
    } catch (e) {
      /* bridge not available (e.g. opened in a normal browser) - ignore */
    }
  }

  function videoEl() {
    return document.querySelector("video");
  }

  function moviePlayer() {
    return document.querySelector("#movie_player");
  }

  /* ---------- metadata ---------- */

  // YouTube Music populates navigator.mediaSession itself for OS integration.
  // That is a public, stable API, so prefer it over scraping internal class names.
  function fromMediaSession() {
    var md = navigator.mediaSession && navigator.mediaSession.metadata;
    if (!md || !md.title) return null;

    var art = "";
    if (md.artwork && md.artwork.length) {
      // pick the largest declared size
      var best = md.artwork[0];
      var bestArea = 0;
      for (var i = 0; i < md.artwork.length; i++) {
        var s = (md.artwork[i].sizes || "").split("x");
        var area = (parseInt(s[0], 10) || 0) * (parseInt(s[1], 10) || 0);
        if (area >= bestArea) { bestArea = area; best = md.artwork[i]; }
      }
      art = best.src || "";
    }
    return {
      title: md.title || "",
      artist: md.artist || "",
      album: md.album || "",
      artwork: art
    };
  }

  // Fallback only. These selectors are Google's internals and will rot.
  function fromDOM() {
    function text(sel) {
      var el = document.querySelector(sel);
      return el ? (el.textContent || "").trim() : "";
    }
    var title = text(".title.ytmusic-player-bar");
    var sub = text(".subtitle.ytmusic-player-bar") || text(".byline.ytmusic-player-bar");

    // subtitle is "Artist • Album • Year"
    var parts = sub.split("•").map(function (p) { return p.trim(); });
    var img = document.querySelector(
      ".ytmusic-player-bar .thumbnail-image-wrapper img, .ytmusic-player-bar img, #thumbnail img"
    );
    return {
      title: title,
      artist: parts[0] || "",
      album: parts[1] || "",
      artwork: img ? img.src || "" : ""
    };
  }

  function readState() {
    var v = videoEl();
    var meta = fromMediaSession() || fromDOM();

    return {
      type: "state",
      title: meta.title,
      artist: meta.artist,
      album: meta.album,
      artwork: meta.artwork,
      isPlaying: v ? !v.paused && !v.ended && v.readyState > 2 : false,
      elapsed: v ? v.currentTime || 0 : 0,
      duration: v && isFinite(v.duration) ? v.duration : 0,
      volume: v ? v.volume : 1,
      hasPlayer: !!v
    };
  }

  var last = null;

  function significantChange(a, b) {
    if (!a) return true;
    if (a.title !== b.title || a.artist !== b.artist) return true;
    if (a.isPlaying !== b.isPlaying || a.hasPlayer !== b.hasPlayer) return true;
    if (Math.abs(a.duration - b.duration) > 0.5) return true;
    // report position roughly once a second while it drifts normally,
    // and immediately on a seek
    if (Math.abs(a.elapsed - b.elapsed) > 0.9) return true;
    return false;
  }

  function publish(force) {
    var s = readState();
    if (force || significantChange(last, s)) {
      last = s;
      send(s);
    }
  }

  /* ---------- controls, called from Swift via evaluateJavaScript ---------- */

  function clickFirst(selectors) {
    for (var i = 0; i < selectors.length; i++) {
      var el = document.querySelector(selectors[i]);
      if (el) { el.click(); return true; }
    }
    return false;
  }

  window.__eym = {
    playPause: function () {
      var v = videoEl();
      if (v) { v.paused ? v.play() : v.pause(); }
      else { clickFirst(["#play-pause-button", ".play-pause-button"]); }
      setTimeout(function () { publish(true); }, 150);
    },

    play: function () {
      var v = videoEl();
      if (v && v.paused) { v.play(); setTimeout(function () { publish(true); }, 150); }
    },

    pause: function () {
      var v = videoEl();
      if (v && !v.paused) { v.pause(); setTimeout(function () { publish(true); }, 150); }
    },

    next: function () {
      var p = moviePlayer();
      if (p && typeof p.nextVideo === "function") { p.nextVideo(); }
      else { clickFirst([".next-button", 'tp-yt-paper-icon-button.next-button', '[aria-label="Next"]']); }
      setTimeout(function () { publish(true); }, 600);
    },

    previous: function () {
      // YouTube Music restarts the track if you are past the first seconds,
      // which matches what the web UI's own button does.
      var p = moviePlayer();
      if (p && typeof p.previousVideo === "function") { p.previousVideo(); }
      else { clickFirst([".previous-button", '[aria-label="Previous"]']); }
      setTimeout(function () { publish(true); }, 600);
    },

    seek: function (seconds) {
      var v = videoEl();
      if (v) { v.currentTime = seconds; publish(true); }
    },

    setVolume: function (level) {
      var v = videoEl();
      if (v) { v.volume = Math.max(0, Math.min(1, level)); publish(true); }
    },

    toggleShuffle: function () {
      clickFirst(["#expand-shuffle", '[aria-label="Shuffle"]', "ytmusic-player-bar .shuffle"]);
    },

    toggleRepeat: function () {
      clickFirst(["#expand-repeat", '[aria-label="Repeat"]', "ytmusic-player-bar .repeat"]);
    },

    refresh: function () { publish(true); }
  };

  /* ---------- wiring ---------- */

  // The <video> element is replaced as you navigate, so re-attach periodically.
  function attach() {
    var v = videoEl();
    if (!v || v.__eymAttached) return;
    v.__eymAttached = true;

    ["play", "pause", "ended", "loadedmetadata", "seeked", "volumechange"].forEach(function (ev) {
      v.addEventListener(ev, function () { publish(true); });
    });
    publish(true);
  }

  attach();
  setInterval(attach, 2000);
  setInterval(function () { publish(false); }, POLL_MS);

  send({ type: "ready" });
})();
