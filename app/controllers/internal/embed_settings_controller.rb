class Internal::EmbedSettingsController < Internal::ApplicationController
  def show
    @settings = EmbedFrameAncestors.current
  end

  def update
    @settings = EmbedFrameAncestors.new(raw: params.dig(:embed_frame_ancestors, :raw))

    if @settings.save
      redirect_to internal_embed_settings_path,
                  notice: @settings.blocked? ? "Partner embedding is now blocked." : "Partner sites updated."
    else
      flash.now[:alert] = "Nothing was saved."
      render :show, status: :unprocessable_entity
    end
  rescue Redis::BaseError, Errno::ECONNREFUSED => e
    Rails.logger.error("[embed settings] redis unavailable: #{e.message}")
    redirect_to internal_embed_settings_path, alert: "Could not reach Redis; nothing was saved."
  end
end
