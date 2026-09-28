// Status poll for the embedded player.
//
// Deliberately a separate file from polling.js rather than a shared module: this runs
// inside seven third-party pages, must stay dependency-free, and must be deployable
// without any chance of disturbing the on-site poller.
//
// The reload is an enforcement mechanism, not just a state transition — it is how a
// viewer gets pulled off a player they should not be seeing. On reload the route can
// return a denial state and sign nothing.
export function initializeEmbedPolling({
  eventSlug, eventStatus, forceReloadVersion, sessionId, sourceToken, enabled, initialTtl
}) {
  const startedAt = new Date().toISOString();
  const pageLoadedAt = Date.now();
  // Set once, on the player's first play. The page being open doesn't mean anything
  // played, so this is what separates plays from page opens.
  let playedAt = null;
  let lastPoll = null;
  const minTtl = 5000;

  let timer = null;

  function poll(timeout, currentStatus, currentVersion) {
    clearTimeout(timer);
    lastPoll = [timeout, currentStatus, currentVersion];

    fetch(`/embed/${encodeURIComponent(eventSlug)}/status`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: JSON.stringify({
        session_id: sessionId,
        event_status: eventStatus,
        started_at: startedAt,
        played_at: playedAt,
        source_token: sourceToken,
        enabled: enabled ? 'true' : 'false'
      })
    })
      .then(async (response) => {
        if (response.status === 404) {
          window.location.reload();
          return;
        }

        const isJson = response.headers.get('content-type')?.includes('application/json');
        const data = isJson && (await response.json());

        if (!response.ok) {
          throw new Error(data?.message || response.status);
        }

        if (
          (data.status !== currentStatus || data.force_reload_version !== currentVersion) &&
          Date.now() - pageLoadedAt > timeout
        ) {
          window.location.reload();
          return;
        }

        const next = Math.max(minTtl, data.ttl || timeout);
        timer = setTimeout(() => poll(next, data.status, data.force_reload_version), next);
      })
      .catch(() => {
        const next = timeout * 1.25;
        timer = setTimeout(() => poll(next, currentStatus, currentVersion), next);
      });
  }

  // Report the first play straight away rather than on the next poll, which can be a
  // while off; the viewer may be gone by then.
  document.querySelector('mux-player')?.addEventListener('play', () => {
    if (playedAt) return;
    playedAt = new Date().toISOString();
    if (lastPoll) poll(...lastPoll);
  });

  poll(Math.max(minTtl, initialTtl || minTtl), eventStatus, forceReloadVersion);
}
