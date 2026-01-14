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

  def mux_player(playback_id:, title:, video_id:, live: false)
    attrs = {
      "playback-id" => playback_id,
      "metadata-video-title" => title,
      "metadata-video-id" => video_id,
      "accent-color" => "#dc0028"
    }
    attrs["redundant-streams"] = "" if live

    attr_string = attrs.map { |k, v| v.empty? ? k : "#{k}=\"#{ERB::Util.html_escape(v)}\"" }.join("\n  ")

    %(<script src="https://cdn.jsdelivr.net/npm/@mux/mux-player"></script>
<mux-player
  #{attr_string}
></mux-player>).html_safe
  end
end
