# Frames a real embed exactly as a partner's page would, so it can be confirmed working
# before anyone is told it is.
#
# Two kinds of preview:
#   - an embeddable event, framed through embed.js: the delivery path partners use.
#   - a live stream that is not live yet, framed directly with a signed pass so the
#     encoder feed can be checked before Go Live. Partners keep seeing the slate.
class Internal::EmbedPreviewsController < Internal::ApplicationController
  def show
    @live_previews = Event.live_previewable
    @recent = Event.embeddable.by_date.limit(10)

    @event =
      if params[:slug].present?
        Event.find_by(slug: params[:slug])
      else
        @recent.first || @live_previews.first
      end

    @live_preview = @event.present? && !@event.embeddable? && @event.live_previewable?
    @preview_token = EmbedPreviewPass.generate(@event) if @live_preview

    @frame_ancestors = EmbedFrameAncestors.header_value
    @partners = EmbedFrameAncestors.current.origins
  end
end
