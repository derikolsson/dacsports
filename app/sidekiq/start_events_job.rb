class StartEventsJob
  include Sidekiq::Job

  def perform
    Event.upcoming
         .where.not(start_at: nil)
         .where("start_at <= ?", 10.minutes.from_now)
         .each do |event|
      event.go_live! if event.can_go_live?
    end
  end
end
