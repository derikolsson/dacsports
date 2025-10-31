class Internal::UploadsController < Internal::ApplicationController
  def index
    # Main uploader page
  end

  def create_upload_url
    # Create a Mux direct upload URL
    require "net/http"
    require "uri"
    require "json"

    uri = URI.parse("https://api.mux.com/video/v1/uploads")
    request = Net::HTTP::Post.new(uri)
    request.basic_auth(
      Rails.application.credentials.dig(:mux, :token_id),
      Rails.application.credentials.dig(:mux, :token_secret)
    )
    request.content_type = "application/json"
    request.body = JSON.dump({
      "new_asset_settings" => {
        "playback_policy" => ["public"],
        "encoding_tier" => "baseline"
      },
      "cors_origin" => request.base_url
    })

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    if response.code == "201"
      upload_data = JSON.parse(response.body)
      render json: { upload_url: upload_data.dig("data", "url") }
    else
      render json: { error: "Failed to create upload URL" }, status: :unprocessable_entity
    end
  end
end
