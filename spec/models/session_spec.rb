require 'rails_helper'

RSpec.describe Session, type: :model do
  describe 'associations' do
    it { should have_many(:event_visits).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:visitor_id) }
  end

  describe '#active?' do
    it 'returns true when last_seen_at is within 3 minutes' do
      session = build(:session, last_seen_at: 2.minutes.ago)
      expect(session.active?).to be true
    end

    it 'returns false when last_seen_at is older than 3 minutes' do
      session = build(:session, last_seen_at: 5.minutes.ago)
      expect(session.active?).to be false
    end
  end

  describe '#parse_user_agent!' do
    let(:session) { create(:session, user_agent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15', browser_name: nil, os_name: nil, device_type: nil) }

    it 'parses user agent and updates browser, OS, and device type' do
      session.parse_user_agent!
      session.reload

      expect(session.browser_name).to be_present
      expect(session.os_name).to be_present
      expect(session.device_type).to be_present
    end

    it 'does nothing when user_agent is blank' do
      session.update_column(:user_agent, nil)
      expect { session.parse_user_agent! }.not_to change { session.reload.browser_name }
    end
  end
end
