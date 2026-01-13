module ApplicationHelper
  def team_badge(team)
    content_tag(:span, team.abbreviation,
      class: "team-badge",
      style: "background-color: #{team.primary_color}; color: #fff;",
      title: team.name)
  end

  def team_chip(team)
    link_to team_path(team.slug),
      class: "team-chip",
      style: "background-color: color-mix(in srgb, #{team.primary_color} 12%, white); color: #{team.text_color};" do
      team_badge(team) + content_tag(:span, team.name, class: "team-chip-name")
    end
  end
end
