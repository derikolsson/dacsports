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

  // A branded cover sits over the frame from the first paint.
  //
  // Without it the browser paints its own "refused to connect" page for however long we
  // wait before deciding the frame is not coming — so a partner who is not approved
  // sees grey browser chrome first and our message second. The cover means they only
  // ever see ours, and it doubles as a loading state on a slow connection.
  var cover = document.createElement("div");
  cover.setAttribute("role", "note");
  cover.setAttribute("aria-live", "polite");
  cover.style.cssText =
    "position:absolute;inset:0;z-index:1;display:flex;flex-direction:column;" +
    "align-items:center;justify-content:center;gap:.5rem;padding:1.5rem;text-align:center;" +
    "background:#0b0b0c;color:#f5f5f5;" +
    "font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;";

  var brand = document.createElement("div");
  brand.textContent = "DAC SPORTS NETWORK";
  brand.style.cssText =
    "font-size:1.05rem;letter-spacing:.1em;color:#f5f5f5;font-weight:700;";
  cover.appendChild(brand);

  // One line under the brand, used first for "Loading" and then, if it comes to it, for
  // the refusal. Reusing the element means the card gains a line rather than swapping
  // one block for another.
  var status = document.createElement("p");
  status.style.cssText =
    "margin:0;font-size:.85rem;font-weight:400;color:#a1a1aa;max-width:34rem;line-height:1.45;";

  function setStatus(text) {
    status.textContent = text;
    if (!status.parentNode) cover.appendChild(status);
  }

  wrapper.appendChild(iframe);
  wrapper.appendChild(cover);

  // The frame reports in once it renders. Silence means it never got to run — most
  // often because this page is not on the approved list, but equally a network failure
  // or a bad slug.
  var READY_TIMEOUT_MS = 6000;
  // Held back deliberately. The frame reports in well inside this on a normal
  // connection, so showing "Loading" immediately would flash it up and tear it down
  // again on every successful load — worse than a card that simply sits still.
  var LOADING_DELAY_MS = 600;
  var settled = false;
  var timer = null;
  var loadingTimer = null;

  function onMessage(event) {
    if (event.origin !== origin) return;
    var data = event.data;
    if (!data || data.source !== "dac-sports-network" || data.type !== "ready") return;
    reveal();
  }

  function reveal() {
    if (settled) return;
    settled = true;
    clearTimeout(timer);
    clearTimeout(loadingTimer);
    window.removeEventListener("message", onMessage);
    if (cover.parentNode) cover.parentNode.removeChild(cover);
  }

  var MESSAGES = {
    unauthorized: "This page is not authorized to display this content.",
    not_found: "This broadcast isn't available.",
    // The frame failed for some other reason — our outage, the network, an extension.
    // Saying "not authorized" here would send someone after the wrong problem.
    unavailable: "This content couldn't be loaded."
  };

  function showUnavailable() {
    if (settled) return;
    settled = true;
    clearTimeout(loadingTimer);
    window.removeEventListener("message", onMessage);
    if (iframe.parentNode) iframe.parentNode.removeChild(iframe);

    // All we observed is that the frame never reported in, which is equally true of a
    // block, a network failure and an ad blocker. Ask before naming a cause.
    setStatus(MESSAGES.unavailable);

    try {
      fetch(origin + "/embed/" + encodeURIComponent(slug) + "/check", {
        mode: "cors",
        credentials: "omit",
        cache: "no-store"
      })
        .then(function (response) {
          return response.ok ? response.json() : null;
        })
        .then(function (data) {
          if (data && MESSAGES[data.reason]) setStatus(MESSAGES[data.reason]);
        })
        .catch(function () {
          // Cannot reach us at all, so "couldn't be loaded" is already the right answer.
        });
    } catch (e) {}
  }

  function startTimer() {
    if (timer || settled) return;
    loadingTimer = setTimeout(function () {
      if (!settled) setStatus("Loading\u2026");
    }, LOADING_DELAY_MS);
    timer = setTimeout(showUnavailable, READY_TIMEOUT_MS);
  }

  window.addEventListener("message", onMessage);

  if (script.parentNode) {
    script.parentNode.insertBefore(wrapper, script.nextSibling);
  } else {
    document.body.appendChild(wrapper);
  }

  // The frame is lazily loaded, so one placed below the fold does not start fetching
  // until it is scrolled to. Starting the clock on insertion would declare it
  // unauthorized while it was simply waiting its turn.
  if (window.IntersectionObserver) {
    var observer = new IntersectionObserver(function (entries) {
      for (var i = 0; i < entries.length; i++) {
        if (entries[i].isIntersecting) {
          observer.disconnect();
          startTimer();
          return;
        }
      }
    });
    observer.observe(wrapper);
  } else {
    startTimer();
  }
})();
