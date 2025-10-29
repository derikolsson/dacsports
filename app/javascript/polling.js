export function initializePolling({ eventSlug, eventId, eventStatus, forceReloadVersion, sessionId, enabled, initialTtl }) {
  const visitId = crypto.randomUUID();
  const startedAt = new Date().toISOString();
  const pageLoadedAt = Date.now();

  let eventStatusTimeout = null;

  function eventStatusPoll(timeout, currentStatus, currentVersion) {
    clearTimeout(eventStatusTimeout);

    const requestOptions = {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        visit_id: visitId,
        session_id: sessionId,
        event_id: eventId,
        event_status: eventStatus,
        started_at: startedAt,  // Tracks when viewer first started watching (for duration analytics)
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

  // Start polling with initial TTL from Redis config
  eventStatusPoll(initialTtl, eventStatus, forceReloadVersion);
}
