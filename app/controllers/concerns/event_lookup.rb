# Resolves an event from a slug, following renamed-slug history.
#
# Extracted from EventsController#show / #status, which each carried their own copy of
# this fallback. EmbedsController would have been the third.
module EventLookup
  extend ActiveSupport::Concern

  # Returns [event, redirect_needed]. redirect_needed is true when the slug matched a
  # retired slug, so callers that serve HTML can 301 to the current one.
  def find_event_by_slug(slug)
    event = Event.find_by(slug: slug)
    return [ event, false ] if event

    retired = EventSlug.find_by(slug: slug)
    retired&.event ? [ retired.event, true ] : [ nil, false ]
  end
end
