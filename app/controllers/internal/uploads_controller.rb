class Internal::UploadsController < Internal::ApplicationController
  def index
    # Main uploader page
  end

  def create_upload_url
    # Configure Mux client
    MuxRuby.configure do |config|
      config.username = Rails.application.credentials.dig(:mux, :token_id)
      config.password = Rails.application.credentials.dig(:mux, :token_secret)
    end

    # Create asset settings
    create_asset_request = MuxRuby::CreateAssetRequest.new
    create_asset_request.playback_policy = [ MuxRuby::PlaybackPolicy::PUBLIC ]
    create_asset_request.video_quality = "premium" # Options: 'basic' (free), 'plus', 'premium' (best for sports)

    # Create upload request
    create_upload_request = MuxRuby::CreateUploadRequest.new
    create_upload_request.new_asset_settings = create_asset_request
    create_upload_request.cors_origin = request.base_url
    create_upload_request.timeout = 3600 # 1 hour timeout

    # Create the direct upload
    uploads_api = MuxRuby::DirectUploadsApi.new
    upload = uploads_api.create_direct_upload(create_upload_request)

    render json: { upload_url: upload.data.url }
  rescue StandardError => e
    Rails.logger.error("Mux Upload Error: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
