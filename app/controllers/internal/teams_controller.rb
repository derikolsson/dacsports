class Internal::TeamsController < Internal::ApplicationController
  before_action :set_team, only: [ :edit, :update, :destroy ]

  def index
    @teams = Team.alphabetical
  end

  def new
    @team = Team.new
  end

  def create
    @team = Team.new(team_params)
    if @team.save
      redirect_to internal_teams_path, notice: "Team created successfully"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @team.update(team_params)
      redirect_to internal_teams_path, notice: "Team updated successfully"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @team.events.any?
      redirect_to internal_teams_path, alert: "Cannot delete team with associated events"
    else
      @team.destroy
      redirect_to internal_teams_path, notice: "Team deleted successfully"
    end
  end

  private

  def set_team
    @team = Team.find(params[:id])
  end

  def team_params
    params.require(:team).permit(:name, :slug)
  end
end
