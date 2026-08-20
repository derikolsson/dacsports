module EmbedsHelper
  # Copy for the states where no player is shown and no token is signed. Mirrors what
  # the on-site watch page says so a partner viewer sees the same story we do.
  def embed_slate_message(event)
    case event.status
    when "upcoming"
      starts = event.start_at&.in_time_zone(event.time_zone)&.strftime("%A, %B %-d at %-I:%M %p %Z")
      starts.present? ? "This stream begins #{starts}." : "This stream hasn't started yet."
    when "ended"
      "This broadcast has concluded."
    when "replay_pending"
      "A replay of this broadcast will be available shortly."
    when "technical_difficulties"
      "We're experiencing technical difficulties — stand by. The full replay will be posted later."
    else
      "This broadcast isn't available right now."
    end
  end
end
