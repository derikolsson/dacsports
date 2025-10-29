export function initializeKeepalive(sessionId, initialTimeout) {
  let keepaliveTimeout = null;

  function keepalive(timeout) {
    clearTimeout(keepaliveTimeout);

    const requestOptions = {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ session_id: sessionId })
    };

    fetch('/sessions/keepalive', requestOptions)
      .then(async response => {
        const isJson = response.headers.get('content-type')?.includes('application/json');
        const data = isJson && await response.json();

        if (!response.ok) {
          throw new Error(data?.message || response.status);
        }

        keepaliveTimeout = setTimeout(() => {
          keepalive(data.timeout);
        }, data.timeout);
      })
      .catch(error => {
        console.error('Keepalive error:', error);
        const newTimeout = timeout * 1.25; // Exponential backoff
        keepaliveTimeout = setTimeout(() => {
          keepalive(newTimeout);
        }, newTimeout);
      });
  }

  // Start keepalive polling with initial timeout from server
  keepalive(initialTimeout);
}
