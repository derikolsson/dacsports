require 'rails_helper'

RSpec.describe EventVisit, type: :model do
  describe 'associations' do
    it { should belong_to(:session) }
    it { should belong_to(:event) }
  end

  describe 'validations' do
    it { should validate_presence_of(:event_status) }
    it { should validate_inclusion_of(:event_status).in_array(%w[live vod]) }
  end

  describe 'event status tracking' do
    it 'allows live status' do
      visit = build(:event_visit, :live)
      expect(visit).to be_valid
    end

    it 'allows vod status' do
      visit = build(:event_visit, :vod)
      expect(visit).to be_valid
    end

    it 'does not allow other statuses' do
      visit = build(:event_visit, event_status: 'upcoming')
      expect(visit).not_to be_valid
      expect(visit.errors[:event_status]).to include('is not included in the list')
    end
  end
end
