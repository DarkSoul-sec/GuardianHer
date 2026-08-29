/*
 * GuardianHer live page renderer (Phase 3J).
 *
 * Vanilla ES2020, zero dependencies. Polls the public API for the token in
 * the URL and renders an OSM raster slippy map. The only third-party origin
 * contacted is tile.openstreetmap.org (required attribution shown).
 *
 * Transport: polling every 5 s while the tab is visible — simplest reliable
 * mechanism that works through any proxy; see live_page.py for rationale.
 */
(function () {
  "use strict";

  var POLL_MS = 5000;
  var STALE_AFTER_MS = 120000;
  var MIN_ZOOM = 3;
  var MAX_ZOOM = 18;
  var TILE_SIZE = 256;

  function $(id) {
    return document.getElementById(id);
  }

  var els = {
    badge: $("live-badge"),
    statusLine: $("status-line"),
    staleBanner: $("stale-banner"),
    map: $("map"),
    tiles: $("tiles"),
    marker: $("marker"),
    circle: $("accuracy-circle"),
    zoomIn: $("zoom-in"),
    zoomOut: $("zoom-out"),
    ended: $("ended-overlay"),
    revoked: $("revoked-overlay"),
  };

  var state = {
    token: null,
    pollTimer: null,
    tickTimer: null,
    lastPayload: null,
    zoom: 16,
  };

  // ---------- helpers ----------

  function show(el) {
    el.classList.remove("hidden");
  }

  function hide(el) {
    el.classList.add("hidden");
  }

  function relativeAge(capturedIso) {
    var ageMs = Date.now() - Date.parse(capturedIso);
    if (!(ageMs >= 0)) ageMs = 0;
    var seconds = Math.round(ageMs / 1000);
    if (seconds < 10) return "just now";
    if (seconds < 60) return seconds + " seconds ago";
    var minutes = Math.floor(seconds / 60);
    return minutes + " minute" + (minutes === 1 ? "" : "s") + " ago";
  }

  function formatClock(iso) {
    var date = new Date(iso);
    if (isNaN(date.getTime())) return "";
    return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  }

  // Web-mercator projection → world pixel coordinates at a zoom level.
  function project(lat, lng, zoom) {
    var scale = TILE_SIZE * Math.pow(2, zoom);
    var x = ((lng + 180) / 360) * scale;
    var clampedLat = Math.max(Math.min(lat, 85.05112878), -85.05112878);
    var rad = (clampedLat * Math.PI) / 180;
    var y =
      (0.5 -
        Math.log(Math.tan(rad) + 1 / Math.cos(rad)) / (2 * Math.PI)) *
      scale;
    return { x: x, y: y };
  }

  // Meters → on-screen pixels at this latitude/zoom.
  function metersToPixels(meters, lat, zoom) {
    var metersPerPixel =
      (156543.03392 * Math.cos((lat * Math.PI) / 180)) /
      Math.pow(2, zoom);
    return Math.max(meters / metersPerPixel, 12);
  }

  // ---------- map rendering ----------

  var tilePool = new Map(); // "z/x/y" -> <img>

  function renderMap(payload) {
    var lat = payload.latitude;
    var lng = payload.longitude;
    var width = els.map.clientWidth;
    var height = els.map.clientHeight;
    if (!width || !height) return;

    var center = project(lat, lng, state.zoom);

    // Tile grid covering the viewport.
    var leftPx = center.x - width / 2;
    var topPx = center.y - height / 2;
    var firstX = Math.floor(leftPx / TILE_SIZE);
    var lastX = Math.floor((leftPx + width) / TILE_SIZE);
    var firstY = Math.floor(topPx / TILE_SIZE);
    var lastY = Math.floor((topPx + height) / TILE_SIZE);
    var maxTile = Math.pow(2, state.zoom);
    var needed = new Set();

    for (var tx = firstX; tx <= lastX; tx++) {
      for (var ty = firstY; ty <= lastY; ty++) {
        if (ty < 0 || ty >= maxTile) continue;
        var wrappedX = ((tx % maxTile) + maxTile) % maxTile;
        var key = state.zoom + "/" + wrappedX + "/" + ty;
        needed.add(key);
        var img = tilePool.get(key);
        if (!img) {
          img = document.createElement("img");
          img.alt = "";
          img.width = TILE_SIZE;
          img.height = TILE_SIZE;
          img.src = "https://tile.openstreetmap.org/" + key + ".png";
          tilePool.set(key, img);
          els.tiles.appendChild(img);
        }
        img.style.left = tx * TILE_SIZE - leftPx + "px";
        img.style.top = ty * TILE_SIZE - topPx + "px";
      }
    }
    tilePool.forEach(function (img, key) {
      if (!needed.has(key)) {
        img.remove();
        tilePool.delete(key);
      }
    });

    // Marker + accuracy circle.
    var screenX = width / 2;
    var screenY = height / 2;
    els.marker.style.left = screenX + "px";
    els.marker.style.top = screenY + "px";
    show(els.marker);

    var diameter = metersToPixels(payload.accuracy_meters || 0, lat, state.zoom) * 2;
    diameter = Math.min(diameter, Math.max(width, height) * 1.5);
    els.circle.style.left = screenX + "px";
    els.circle.style.top = screenY + "px";
    els.circle.style.width = diameter + "px";
    els.circle.style.height = diameter + "px";
    show(els.circle);
  }

  function setZoom(delta) {
    state.zoom = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, state.zoom + delta));
    if (state.lastPayload) renderMap(state.lastPayload);
  }

  // ---------- status rendering ----------

  function renderActive(payload) {
    hide(els.ended);
    hide(els.revoked);
    show(els.map);
    show(els.statusLine);
    state.lastPayload = payload;

    var ageMs = Date.now() - Date.parse(payload.captured_at);
    var stale = !(ageMs <= STALE_AFTER_MS);
    els.badge.textContent = stale ? "● LIVE" : "● LIVE";
    els.badge.classList.toggle("stale", stale);
    show(els.badge);

    els.staleBanner.classList.toggle("hidden", !stale);

    els.statusLine.textContent =
      "Last updated: " + relativeAge(payload.captured_at) +
      " · Accuracy: " + Math.round(payload.accuracy_meters) + " m" +
      " · Expires: " + formatClock(payload.expires_at);

    renderMap(payload);
  }

  function renderEnded() {
    stopPolling();
    hide(els.badge);
    hide(els.staleBanner);
    hide(els.map);
    hide(els.statusLine);
    show(els.ended);
  }

  function renderRevoked() {
    stopPolling();
    hide(els.badge);
    hide(els.staleBanner);
    hide(els.map);
    hide(els.statusLine);
    show(els.revoked);
  }

  // ---------- polling ----------

  function handleResponse(body) {
    if (body && body.status === "revoked") {
      renderRevoked();
      return;
    }
    if (!body || body.status !== "active") {
      // Unknown AND expired tokens share the {"status": "ended"} body.
      renderEnded();
      return;
    }
    renderActive(body);
  }

  function poll() {
    fetch("/api/v1/live-sessions/" + state.token, { cache: "no-store" })
      .then(function (res) {
        return res.json().catch(function () { return null; });
      })
      .then(handleResponse)
      .catch(function () {
        // Transient network trouble: keep the current view, retry next tick.
      });
  }

  function startPolling() {
    stopPolling();
    poll();
    state.pollTimer = setInterval(function () {
      if (document.visibilityState === "visible") poll();
    }, POLL_MS);
    // Keep "N seconds ago" fresh between polls.
    state.tickTimer = setInterval(function () {
      if (state.lastPayload) renderActive(state.lastPayload);
    }, 1000);
  }

  function stopPolling() {
    if (state.pollTimer) clearInterval(state.pollTimer);
    if (state.tickTimer) clearInterval(state.tickTimer);
    state.pollTimer = null;
    state.tickTimer = null;
  }

  // ---------- boot ----------

  function init() {
    var segments = window.location.pathname.split("/").filter(Boolean);
    var token = segments[segments.length - 1];
    if (!token || !/^[A-Za-z0-9_-]{43}$/.test(token)) {
      renderEnded();
      return;
    }
    state.token = token;

    els.zoomIn.addEventListener("click", function () { setZoom(1); });
    els.zoomOut.addEventListener("click", function () { setZoom(-1); });
    window.addEventListener("resize", function () {
      if (state.lastPayload) renderMap(state.lastPayload);
    });

    startPolling();
  }

  init();
})();
