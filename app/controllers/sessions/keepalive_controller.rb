class Sessions::KeepaliveController < ApplicationController
  skip_forgery_protection

  def create
    SessionKeepaliveJob.perform_async(params[:session_id], Time.current.to_s)
    render json: { timeout: Dacsports.redis.get("keepalive_timeout").to_i }, status: :accepted
  end
end
