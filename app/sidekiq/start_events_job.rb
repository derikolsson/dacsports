class StartEventsJob
  include Sidekiq::Job

  def perform
    Event.upcoming
         .where.not(stream_starts_at: nil)
         .where("stream_starts_at <= ?", Time.current)
         .each do |event|
      event.go_live! if event.can_go_live?
    end
  end
end
