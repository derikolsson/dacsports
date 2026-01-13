class TeamsController < ApplicationController
  def index
    @title = "Teams"
    @teams = Team.alphabetical
  end

  def show
    @team = Team.find_by!(slug: params[:slug])
    @title = @team.name
    @upcoming_events = @team.events.visible.upcoming_events.includes(:teams).order(start_at: :asc)
    @past_events = @team.events.visible.past.includes(:teams).order(start_at: :desc).limit(10)
  end
end
