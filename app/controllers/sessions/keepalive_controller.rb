class Sessions::KeepaliveController < ApplicationController
  skip_forgery_protection

  def create
    SessionKeepaliveJob.perform_async(params[:session_id], Time.current.to_s)
    render json: { timeout: 60000 }, status: :accepted # 60 seconds
  end
end
