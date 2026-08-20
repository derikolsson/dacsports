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

  var ORIGIN = "https://dacsports.net";

  // document.currentScript is correct during synchronous execution; the querySelector
  // fallback covers deferred/async loading where currentScript is null.
  var script =
    document.currentScript ||
    (function () {
      var all = document.querySelectorAll("script[data-stream]");
      return all.length ? all[all.length - 1] : null;
    })();

  if (!script) return;

  var slug = script.getAttribute("data-stream");
  if (!slug) return;

  function truncate(value) {
    value = value || "";
    return value.length > 1024 ? value.slice(0, 1024) : value;
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

  var src = ORIGIN + "/embed/" + encodeURIComponent(slug);
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

  if (script.parentNode) {
    script.parentNode.insertBefore(wrapper, script.nextSibling);
  } else {
    document.body.appendChild(wrapper);
  }
})();
