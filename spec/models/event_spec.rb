require 'rails_helper'

RSpec.describe Event, type: :model do
  describe 'validations' do
    subject { build(:event) }

    it { should validate_presence_of(:title) }
    it { should validate_presence_of(:start_at) }
    it { should validate_presence_of(:time_zone) }

    it 'validates slug uniqueness' do
      event1 = create(:event)
      event2 = build(:event, slug: event1.slug)
      expect(event2).not_to be_valid
      expect(event2.errors[:slug]).to include('has already been taken')
    end

    it 'validates sport is in the allowed list' do
      event = build(:event, sport: 'InvalidSport')
      expect(event).not_to be_valid
      expect(event.errors[:sport]).to include('is not included in the list')
    end

    it 'allows blank sport' do
      event = build(:event, sport: nil)
      expect(event).to be_valid
    end

    it 'allows valid sports' do
      Event::SPORTS.each do |sport|
        event = build(:event, sport: sport)
        expect(event).to be_valid
      end
    end

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
      replay_available: 'replay_available',
      technical_difficulties: 'technical_difficulties'
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

    describe '#mark_technical_difficulties!' do
      let(:event) { create(:event, :live) }

      it 'transitions from live to technical_difficulties' do
        expect(event.mark_technical_difficulties!).to be true
        expect(event.reload.status).to eq('technical_difficulties')
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

      it 'transitions from technical_difficulties to replay_available' do
        td_event = create(:event, :technical_difficulties, replay_embed_code: '<iframe>replay</iframe>')
        expect(td_event.publish_replay!).to be true
        expect(td_event.reload.status).to eq('replay_available')
      end
    end
  end

  describe '#sport_emoji' do
    it "returns soccer emoji for Men's Soccer" do
      event = build(:event, sport: "Men's Soccer")
      expect(event.sport_emoji).to eq('⚽')
    end

    it "returns soccer emoji for Women's Soccer" do
      event = build(:event, sport: "Women's Soccer")
      expect(event.sport_emoji).to eq('⚽')
    end

    it "returns volleyball emoji for Men's Volleyball" do
      event = build(:event, sport: "Men's Volleyball")
      expect(event.sport_emoji).to eq('🏐')
    end

    it "returns volleyball emoji for Women's Volleyball" do
      event = build(:event, sport: "Women's Volleyball")
      expect(event.sport_emoji).to eq('🏐')
    end

    it "returns basketball emoji for Men's Basketball" do
      event = build(:event, sport: "Men's Basketball")
      expect(event.sport_emoji).to eq('🏀')
    end

    it "returns football emoji for Women's Football" do
      event = build(:event, sport: "Women's Football")
      expect(event.sport_emoji).to eq('🏈')
    end

    it 'matches sport keywords using inclusion' do
      event = build(:event, sport: 'Soccer Tournament')
      expect(event.sport_emoji).to eq('⚽')
    end

    it 'returns empty string for unknown sport' do
      event = build(:event, sport: 'Tennis')
      expect(event.sport_emoji).to eq('')
    end

    it 'returns empty string when sport is nil' do
      event = build(:event, sport: nil)
      expect(event.sport_emoji).to eq('')
    end

    it 'is case insensitive' do
      event = build(:event, sport: 'SOCCER MATCH')
      expect(event.sport_emoji).to eq('⚽')
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

  describe '#related_events' do
    let(:base_event) { create(:event, sport: "Women's Volleyball", start_at: Time.zone.now) }

    context 'when there are related events in the same sport' do
      let!(:related_event_1) { create(:event, sport: "Women's Volleyball", start_at: base_event.start_at + 1.day) }
      let!(:related_event_2) { create(:event, sport: "Women's Volleyball", start_at: base_event.start_at - 2.days) }
      let!(:related_event_3) { create(:event, sport: "Women's Volleyball", start_at: base_event.start_at + 3.days) }

      it 'returns events in the same sport within +/- 3 days' do
        related = base_event.related_events
        expect(related).to include(related_event_1, related_event_2, related_event_3)
        expect(related).not_to include(base_event)
      end

      it 'orders related events chronologically' do
        related = base_event.related_events
        expect(related.first).to eq(related_event_2)
        expect(related.last).to eq(related_event_3)
      end
    end

    context 'when there are events outside the 3-day window' do
      let!(:too_early) { create(:event, sport: "Women's Volleyball", start_at: base_event.start_at - 4.days) }
      let!(:too_late) { create(:event, sport: "Women's Volleyball", start_at: base_event.start_at + 4.days) }

      it 'does not include them' do
        related = base_event.related_events
        expect(related).not_to include(too_early, too_late)
      end
    end

    context 'when there are events in different sports' do
      let!(:different_sport) { create(:event, sport: "Men's Basketball", start_at: base_event.start_at + 1.day) }

      it 'does not include them' do
        related = base_event.related_events
        expect(related).not_to include(different_sport)
      end
    end

    context 'when there are hidden events' do
      let!(:hidden_event) { create(:event, :hidden, sport: "Women's Volleyball", start_at: base_event.start_at + 1.day) }

      it 'does not include them' do
        related = base_event.related_events
        expect(related).not_to include(hidden_event)
      end
    end

    context 'when sport is blank' do
      let(:no_sport_event) { create(:event, sport: nil, start_at: Time.zone.now) }

      it 'returns an empty relation' do
        expect(no_sport_event.related_events).to eq(Event.none)
      end
    end

    context 'when start_at is blank' do
      let(:no_start_event) { build(:event, sport: "Women's Volleyball", start_at: nil) }

      it 'returns an empty relation' do
        expect(no_start_event.related_events).to eq(Event.none)
      end
    end
  end
end
