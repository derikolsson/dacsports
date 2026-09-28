export function initializePolling({ eventSlug, eventId, eventStatus, forceReloadVersion, sessionId, enabled, initialTtl }) {
  const startedAt = new Date().toISOString();
  const pageLoadedAt = Date.now();
  // Set once, on the player's first play. The page being open doesn't mean anything
  // played, so this is what separates plays from page opens.
  let playedAt = null;
  let lastPoll = null;

  let eventStatusTimeout = null;

  function eventStatusPoll(timeout, currentStatus, currentVersion) {
    clearTimeout(eventStatusTimeout);
    lastPoll = [timeout, currentStatus, currentVersion];

    const requestOptions = {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        session_id: sessionId,
        event_id: eventId,
        event_status: eventStatus,
        started_at: startedAt,  // Tracks when viewer first started watching (for duration analytics)
        played_at: playedAt,
        enabled: enabled ? 'true' : 'false'
      })
    };

    fetch(`/events/${eventSlug}/status`, requestOptions)
      .then(async response => {
        const isJson = response.headers.get('content-type')?.includes('application/json');
        const data = isJson && await response.json();

        if (!response.ok) {
          throw new Error(data?.message || response.status);
        }

        // Reload if status changed or version bumped
        if ((data.status !== currentStatus || data.force_reload_version !== currentVersion) &&
            (Date.now() - pageLoadedAt) > timeout) {
          console.log('Reloading due to event status/version change');
          window.location.reload();
          return;
        }

        eventStatusTimeout = setTimeout(() => {
          eventStatusPoll(data.ttl, data.status, data.force_reload_version);
        }, data.ttl);
      })
      .catch(error => {
        console.error('Event status poll error:', error);
        const newTimeout = timeout * 1.25; // Exponential backoff
        eventStatusTimeout = setTimeout(() => {
          eventStatusPoll(newTimeout, currentStatus, currentVersion);
        }, newTimeout);
      });
  }

  // Report the first play straight away rather than on the next poll, which can be a
  // while off; the viewer may be gone by then.
  document.querySelector('mux-player')?.addEventListener('play', () => {
    if (playedAt) return;
    playedAt = new Date().toISOString();
    if (lastPoll) eventStatusPoll(...lastPoll);
  });

  // Start polling with initial TTL from Redis config
  eventStatusPoll(initialTtl, eventStatus, forceReloadVersion);
}
