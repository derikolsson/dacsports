// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import * as bootstrap from "bootstrap"
import { initializeKeepalive } from "keepalive"

// Initialize session keepalive on page load
document.addEventListener('DOMContentLoaded', () => {
  // Get session_id and keepalive timeout from body data attributes
  const sessionId = document.body.dataset.sessionId;
  const keepaliveTimeout = parseInt(document.body.dataset.keepaliveTimeout || '60000');

  if (sessionId) {
    initializeKeepalive(sessionId, keepaliveTimeout);
  }
});
