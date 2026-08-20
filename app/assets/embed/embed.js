/*!
 * DAC Sports Network embed wrapper.
 *
 * Injects an iframe pointing at dacsports.net. It deliberately does NOT inject a player
 * into the host page: keeping playback inside our own origin is the entire security
 * model. Mux sees dacsports.net as the referrer, so the playback restriction holds
 * without us having to track seven partner domains.
 *
 * This file is a single point of failure across every partner site simultaneously.
 * Keep it dependency-free, keep it small, and test it before every deploy.
 */
(function () {
  "use strict";

  var FALLBACK_ORIGIN = "https://dacsports.net";

  // document.currentScript is correct during synchronous execution; the querySelector
  // fallback covers deferred/async loading where currentScript is null.
  var script =
    document.currentScript ||
    (function () {
      var all = document.querySelectorAll("script[data-stream]");
      return all.length ? all[all.length - 1] : null;
    })();

  if (!script) return;

  // Frame the same host that served this script. Keeps the wrapper self-consistent
  // (it cannot point somewhere it was not served from), and lets it be exercised
  // against staging or a local server rather than only production.
  var origin = FALLBACK_ORIGIN;
  try {
    if (script.src) origin = new URL(script.src, window.location.href).origin;
  } catch (e) {
    // Keep the fallback.
  }

  var slug = script.getAttribute("data-stream");
  if (!slug) return;

  function truncate(value) {
    value = value || "";
    return value.length > 1024 ? value.slice(0, 1024) : value;
  }

  // Visitor identity, stored in the PARENT page's storage.
  //
  // This is the whole trick: storage written here belongs to the partner's own origin,
  // so it is first-party and survives third-party cookie blocking. A cookie set inside
  // our iframe is third-party and is dropped outright by Safari, which made every page
  // load look like a brand new viewer.
  //
  // Scoped per partner site by definition — each origin has its own storage — which is
  // exactly the granularity we report at. Safari still clears script-writable storage
  // after a stretch with no interaction, so this is "much better", not "permanent".
  function visitorId() {
    // A partner can decline storage entirely with data-storage="off" — useful if their
    // site runs a consent banner and does not want a write before the user accepts.
    // The player still works; their viewers just count as new each visit.
    if ((script.getAttribute("data-storage") || "").toLowerCase() === "off") return null;

    var key = "dacsn_vid";
    try {
      var existing = window.localStorage.getItem(key);
      if (existing && /^[0-9a-f-]{36}$/.test(existing)) return existing;

      var generated = uuid();
      window.localStorage.setItem(key, generated);
      return generated;
    } catch (e) {
      // Private mode, disabled storage, or a sandboxed parent. The iframe falls back to
      // its own cookie, and failing that a per-load id.
      return null;
    }
  }

  function uuid() {
    try {
      if (window.crypto && window.crypto.randomUUID) return window.crypto.randomUUID();
      var bytes = new Uint8Array(16);
      window.crypto.getRandomValues(bytes);
      bytes[6] = (bytes[6] & 0x0f) | 0x40;
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      var hex = [];
      for (var i = 0; i < 16; i++) hex.push((bytes[i] + 0x100).toString(16).slice(1));
      return (
        hex.slice(0, 4).join("") + "-" + hex.slice(4, 6).join("") + "-" +
        hex.slice(6, 8).join("") + "-" + hex.slice(8, 10).join("") + "-" +
        hex.slice(10, 16).join("")
      );
    } catch (e) {
      return null;
    }
  }

  var params = [];
  try {
    params.push("src=" + encodeURIComponent(truncate(window.location.href)));
    params.push("title=" + encodeURIComponent(truncate(document.title)));
    params.push("ref=" + encodeURIComponent(truncate(document.referrer)));
  } catch (e) {
    // Sandboxed parents can throw on location access. The server-side Referer header
    // is the authoritative record anyway; these params are only enrichment.
  }

  var vid = visitorId();
  if (vid) params.push("v=" + encodeURIComponent(vid));

  var src = origin + "/embed/" + encodeURIComponent(slug);
  if (params.length) src += "?" + params.join("&");

  // A cross-origin iframe cannot size itself, so it needs an aspect-ratio wrapper or it
  // renders as a fixed-height box that breaks on mobile.
  var wrapper = document.createElement("div");
  wrapper.setAttribute("data-dac-embed", slug);
  wrapper.style.cssText = "position:relative;width:100%;aspect-ratio:16/9;background:#000;";

  var iframe = document.createElement("iframe");
  iframe.src = src;
  iframe.title = "DAC Sports Network";
  iframe.loading = "lazy";
  iframe.setAttribute("allowfullscreen", "");
  // Without this, fullscreen / PiP / autoplay are silently dead in a cross-origin frame
  // under Permissions-Policy.
  iframe.setAttribute(
    "allow",
    "autoplay; fullscreen; picture-in-picture; encrypted-media; remote-playback"
  );
  iframe.style.cssText = "position:absolute;inset:0;width:100%;height:100%;border:0;";

  wrapper.appendChild(iframe);

  // The frame reports in once it renders. Silence means it never got to run — most
  // often because this page is not on the approved list yet, but equally a network
  // failure or a bad slug. Either way the partner gets an explanation rather than a
  // black rectangle they cannot diagnose.
  var READY_TIMEOUT_MS = 6000;
  var settled = false;

  function onMessage(event) {
    if (event.origin !== origin) return;
    var data = event.data;
    if (!data || data.source !== "dac-sports-network" || data.type !== "ready") return;
    settled = true;
    window.removeEventListener("message", onMessage);
  }

  window.addEventListener("message", onMessage);

  setTimeout(function () {
    if (settled) return;
    window.removeEventListener("message", onMessage);
    showUnavailable();
  }, READY_TIMEOUT_MS);

  function showUnavailable() {
    wrapper.removeChild(iframe);

    var panel = document.createElement("div");
    panel.setAttribute("role", "note");
    panel.style.cssText =
      "position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;" +
      "justify-content:center;gap:.5rem;padding:1.5rem;text-align:center;background:#0b0b0c;" +
      "color:#f5f5f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;";

    var brand = document.createElement("div");
    brand.textContent = "DAC SPORTS NETWORK";
    brand.style.cssText =
      "font-size:.7rem;letter-spacing:.14em;color:#dc0028;font-weight:700;";

    var heading = document.createElement("p");
    heading.textContent = "This page is not authorized to display this content.";
    heading.style.cssText =
      "margin:0;font-size:1rem;font-weight:600;max-width:34rem;line-height:1.45;";

    panel.appendChild(brand);
    panel.appendChild(heading);
    wrapper.appendChild(panel);
  }

  if (script.parentNode) {
    script.parentNode.insertBefore(wrapper, script.nextSibling);
  } else {
    document.body.appendChild(wrapper);
  }
})();
