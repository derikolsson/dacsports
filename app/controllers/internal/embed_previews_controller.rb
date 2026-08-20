# Frames a real embed exactly as a partner's page would, so it can be confirmed working
# before anyone is told it is.
class Internal::EmbedPreviewsController < Internal::ApplicationController
  def show
    @event =
      if params[:slug].present?
        Event.find_by(slug: params[:slug])
      else
        Event.embeddable.by_date.first
      end

    @recent = Event.embeddable.by_date.limit(10)
    @frame_ancestors = EmbedFrameAncestors.header_value
    @partners = EmbedFrameAncestors.current.origins
  end
end
