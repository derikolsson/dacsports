module ApplicationHelper
  def team_badge(team)
    badge_text = team.team_colors[:text] || "#fff"
    content_tag(:span, team.abbreviation,
      class: "team-badge",
      style: "background-color: #{team.primary_color}; color: #{badge_text};",
      title: team.name)
  end

  def team_chip(team)
    link_to team_path(team.slug),
      class: "team-chip",
      style: "background-color: color-mix(in srgb, #{team.primary_color} 12%, white); color: #{team.text_color};" do
      team_badge(team) + content_tag(:span, team.name, class: "team-chip-name")
    end
  end

  def mux_player(playback_id:, title:, video_id:, live: false, start_time: nil, end_time: nil)
    attrs = {
      "playback-id" => playback_id,
      "metadata-video-title" => title,
      "metadata-video-id" => video_id,
      "accent-color" => "#dc0028"
    }
    attrs["redundant-streams"] = "" if live
    attrs["asset-start-time"] = start_time.to_s if start_time.present?
    attrs["asset-end-time"] = end_time.to_s if end_time.present?

    attr_string = attrs.map { |k, v| v.empty? ? k : "#{k}=\"#{ERB::Util.html_escape(v)}\"" }.join("\n  ")

    %(<script src="https://cdn.jsdelivr.net/npm/@mux/mux-player"></script>
<mux-player
  #{attr_string}
></mux-player>).html_safe
  end

  # Signed player for the embed route. Kept separate from mux_player rather than
  # overloading it: this is a parallel render path, and the on-site player must not be
  # able to regress when the embed changes.
  #
  # Pinned to the current major. Chromecast needs >= 2.3.0, but @2 resolves to 2.9.1,
  # which fires a stray relative fetch against our own origin on every load; @3 does not.
  # Pinned rather than bare so a future major cannot land here without us choosing it —
  # the on-site helper's unpinned URL is a live dependency on whatever Mux ships next.
  def signed_mux_player(playback_id:, tokens:, title:, video_id:, stream_type:, start_time: nil, end_time: nil)
    attrs = {
      "playback-id" => playback_id,
      "stream-type" => stream_type,
      "playback-token" => tokens[:playback],
      "thumbnail-token" => tokens[:thumbnail],
      "metadata-video-title" => title,
      "metadata-video-id" => video_id,
      "accent-color" => "#dc0028"
    }
    # Explicit poster. Left to compute its own, mux-player emits a relative "undefined"
    # URL and the browser fetches it against our origin on every load.
    if tokens[:thumbnail].present?
      attrs["poster"] = "https://image.mux.com/#{playback_id}/thumbnail.webp?token=#{tokens[:thumbnail]}"
    end
    # Storyboards are on-demand only; Mux does not generate them for live.
    attrs["storyboard-token"] = tokens[:storyboard] if tokens[:storyboard].present?
    attrs["redundant-streams"] = "" if stream_type == "live"
    attrs["asset-start-time"] = start_time.to_s if start_time.present?
    attrs["asset-end-time"] = end_time.to_s if end_time.present?

    attr_string = attrs.compact.map { |k, v| v.to_s.empty? ? k : "#{k}=\"#{ERB::Util.html_escape(v)}\"" }.join("\n  ")

    %(<script src="https://cdn.jsdelivr.net/npm/@mux/mux-player@3"></script>
<mux-player
  #{attr_string}
></mux-player>).html_safe
  end
end
