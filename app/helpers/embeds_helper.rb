module EmbedsHelper
  # The snippet handed to a partner, with a comment naming the event.
  #
  # These get copied several at a time into an email, where one bare script tag looks
  # exactly like the next — the comment is what makes a batch of them readable, and it
  # survives into the partner's page so they can tell later which embed is which.
  def embed_snippet_for(event, script_url)
    <<~SNIPPET.strip
      <!-- #{embed_snippet_label(event)} -->
      <script src="#{script_url}" data-stream="#{event.slug}"></script>
    SNIPPET
  end

  def embed_snippet_label(event)
    # Same shape the watch page uses for its own title: "Sport: Title".
    name = [ event.sport.presence, event.title.presence ].compact.join(": ")
    date = event.event_date&.strftime("%b %-d, %Y")

    comment_safe([ name.presence, date ].compact.join(" — "))
  end

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

  private

  # An HTML comment cannot contain "--" and ends at the first ">", so a title carrying
  # either would produce a snippet that breaks the partner's page rather than a comment.
  def comment_safe(text)
    text.to_s.gsub(/[<>]/, "").gsub(/-{2,}/, "-").squish
  end
end
