// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import * as bootstrap from "bootstrap"
import { initializeKeepalive } from "keepalive"

// Initialize session keepalive on page load
document.addEventListener('DOMContentLoaded', () => {
  // Get or create visitor_id
  let visitorId = localStorage.getItem('dac_visitor_id');
  if (!visitorId) {
    visitorId = crypto.randomUUID();
    localStorage.setItem('dac_visitor_id', visitorId);
  }

  // Get session_id from meta tag (set by server)
  const sessionId = document.querySelector('meta[name="session-id"]')?.content;

  if (sessionId) {
    initializeKeepalive(sessionId);
  }
});
