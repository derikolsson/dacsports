require 'rails_helper'

RSpec.describe EventVisitJob do
  let(:event) { create(:event) }
  let(:session) { create(:session, last_seen_at: 20.minutes.ago) }
  let(:seen_at) { Time.current.utc.change(usec: 0) }

  def perform(started_at)
    described_class.new.perform(session.id, event.id, "live", started_at, seen_at.iso8601(6))
  end

  describe 'started_at' do
    it 'keeps a plausible browser timestamp' do
      perform(5.minutes.ago.utc.iso8601)

      expect(EventVisit.last.started_at).to be_within(1.second).of(5.minutes.ago)
    end

    it 'falls back to the server time when missing' do
      perform(nil)

      expect(EventVisit.last.started_at).to eq(seen_at)
    end

    it 'falls back to the server time when unparseable' do
      perform("not a time")

      expect(EventVisit.last.started_at).to eq(seen_at)
    end

    # A fast client clock would otherwise push the visit into a later reporting period.
    it 'never lands after the server time' do
      perform(2.hours.from_now.utc.iso8601)

      expect(EventVisit.last.started_at).to eq(seen_at)
    end
  end

  describe 'session activity' do
    it 'keeps the session alive' do
      perform(nil)

      expect(session.reload.last_seen_at).to eq(seen_at)
    end

    it 'does not move the session backwards' do
      session.update!(last_seen_at: 1.minute.from_now)

      expect { perform(nil) }.not_to(change { session.reload.last_seen_at })
    end
  end
end
