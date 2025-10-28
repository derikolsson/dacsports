require 'rails_helper'

RSpec.describe Event, type: :model do
  describe 'validations' do
    subject { build(:event) }

    it { should validate_presence_of(:title) }
    it { should validate_presence_of(:slug) }
    it { should validate_presence_of(:start_at) }
    it { should validate_presence_of(:time_zone) }
    it { should validate_uniqueness_of(:slug) }

    context 'when status is live' do
      subject { build(:event, :live) }
      it { should validate_presence_of(:live_embed_code) }
    end

    context 'when status is replay_available' do
      subject { build(:event, :replay_available) }
      it { should validate_presence_of(:replay_embed_code) }
    end
  end

  describe 'enums' do
    it { should define_enum_for(:status).with_values(
      upcoming: 'upcoming',
      live: 'live',
      ended: 'ended',
      replay_pending: 'replay_pending',
      replay_available: 'replay_available'
    ).backed_by_column_of_type(:string) }
  end

  describe 'scopes' do
    let!(:visible_event) { create(:event, visible: true) }
    let!(:hidden_event) { create(:event, :hidden) }
    let!(:upcoming_event) { create(:event, :upcoming, start_at: 1.week.from_now) }
    let!(:past_upcoming_event) { create(:event, :upcoming, start_at: 1.week.ago) }
    let!(:live_event) { create(:event, :live) }
    let!(:ended_event) { create(:event, :ended) }
    let!(:replay_event) { create(:event, :replay_available) }

    describe '.visible' do
      it 'returns only visible events' do
        expect(Event.visible).to include(visible_event)
        expect(Event.visible).not_to include(hidden_event)
      end
    end

    describe '.upcoming_events' do
      it 'returns only upcoming events with future or current dates' do
        expect(Event.upcoming_events).to include(upcoming_event)
        expect(Event.upcoming_events).not_to include(past_upcoming_event)
      end
    end

    describe '.past' do
      it 'returns ended, replay_pending, and replay_available events' do
        expect(Event.past).to include(ended_event, replay_event)
        expect(Event.past).not_to include(upcoming_event, live_event)
      end
    end

    describe '.by_date' do
      it 'orders events by start_at descending' do
        events = Event.by_date
        expect(events.first.start_at).to be >= events.last.start_at
      end
    end
  end

  describe '#current_embed_code' do
    it 'returns live_embed_code when status is live' do
      event = build(:event, :live)
      expect(event.current_embed_code).to eq(event.live_embed_code)
    end

    it 'returns replay_embed_code when status is replay_available' do
      event = build(:event, :replay_available)
      expect(event.current_embed_code).to eq(event.replay_embed_code)
    end

    it 'returns nil for other statuses' do
      event = build(:event, :upcoming)
      expect(event.current_embed_code).to be_nil
    end
  end

  describe 'state transitions' do
    describe '#go_live!' do
      let(:event) { create(:event, :upcoming, live_embed_code: '<iframe>live</iframe>') }

      it 'transitions from upcoming to live' do
        expect(event.go_live!).to be true
        expect(event.reload.status).to eq('live')
      end

      it 'returns false when live_embed_code is not present' do
        event.update_column(:live_embed_code, nil)
        expect(event.go_live!).to be false
        expect(event.reload.status).to eq('upcoming')
      end
    end

    describe '#end_event!' do
      let(:event) { create(:event, :live) }

      it 'transitions from live to ended' do
        expect(event.end_event!).to be true
        expect(event.reload.status).to eq('ended')
      end
    end

    describe '#mark_replay_pending!' do
      let(:event) { create(:event, :live) }

      it 'transitions from live to replay_pending' do
        expect(event.mark_replay_pending!).to be true
        expect(event.reload.status).to eq('replay_pending')
      end
    end

    describe '#publish_replay!' do
      let(:event) { create(:event, :replay_pending, replay_embed_code: '<iframe>replay</iframe>') }

      it 'transitions from replay_pending to replay_available' do
        expect(event.publish_replay!).to be true
        expect(event.reload.status).to eq('replay_available')
      end

      it 'returns false when replay_embed_code is not present' do
        event.update_column(:replay_embed_code, nil)
        expect(event.publish_replay!).to be false
        expect(event.reload.status).to eq('replay_pending')
      end
    end
  end

  describe 'cache busting' do
    let(:event) { create(:event) }

    it 'increments force_reload_count when title changes' do
      expect {
        event.update(title: 'New Title')
      }.to change { event.force_reload_count }.by(1)
    end

    it 'increments force_reload_count when status changes' do
      event.update(live_embed_code: '<iframe>live</iframe>')
      expect {
        event.go_live!
      }.to change { event.force_reload_count }.by(1)
    end

    it 'increments force_reload_count when live_embed_code changes' do
      expect {
        event.update(live_embed_code: '<iframe>new</iframe>')
      }.to change { event.force_reload_count }.by(1)
    end

    it 'does not increment force_reload_count for other fields' do
      expect {
        event.update(description: 'New description')
      }.not_to change { event.force_reload_count }
    end
  end
end
