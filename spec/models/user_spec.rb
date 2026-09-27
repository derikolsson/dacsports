require 'rails_helper'

RSpec.describe User, type: :model do
  it 'normalizes the email address' do
    expect(create(:user, email_address: "  Coach@Example.COM ").email_address).to eq("coach@example.com")
  end

  it 'gives every user a WebAuthn handle' do
    expect(create(:user).webauthn_id).to be_present
  end

  describe 'passwords' do
    it 'lets an invitee exist without one' do
      expect(build(:user, :pending)).to be_valid
    end

    it 'requires one once the invitation is accepted' do
      expect(build(:user, password: nil)).not_to be_valid
    end

    it 'requires at least 12 characters' do
      user = build(:user, password: "short")
      expect(user).not_to be_valid
      expect(user.errors[:password].first).to match(/too short/)
    end
  end

  describe '.authenticate' do
    let!(:user) { create(:user, email_address: "coach@example.com") }

    it 'finds an active user with the right password' do
      expect(User.authenticate(email_address: "COACH@example.com", password: "correct horse battery")).to eq(user)
    end

    it 'refuses a wrong password or a deactivated user' do
      expect(User.authenticate(email_address: "coach@example.com", password: "nope")).to be_nil
      user.deactivate!
      expect(User.authenticate(email_address: "coach@example.com", password: "correct horse battery")).to be_nil
    end
  end

  describe '#accept_invitation' do
    let(:user) { create(:user, :pending) }

    it 'sets the password and makes the user active' do
      expect(user.accept_invitation(name: "Pat", password: "a long enough password", password_confirmation: "a long enough password")).to be(true)
      expect(user.reload).to be_active
    end

    it 'stays pending when the password is missing' do
      expect(user.accept_invitation(name: "Pat", password: "", password_confirmation: "")).to be(false)
      expect(user).to be_pending
    end
  end

  describe 'tokens' do
    it 'expires the invitation once accepted' do
      user = create(:user, :pending)
      token = user.generate_token_for(:invitation)
      expect(User.find_by_token_for(:invitation, token)).to eq(user)

      user.accept_invitation(name: "Pat", password: "a long enough password", password_confirmation: "a long enough password")
      expect(User.find_by_token_for(:invitation, token)).to be_nil
    end

    it 'uses a magic link only once' do
      user = create(:user)
      token = user.generate_token_for(:magic_link)
      expect(User.find_active_by_token_for(:magic_link, token)).to eq(user)

      user.update!(last_signed_in_at: Time.current)
      expect(User.find_active_by_token_for(:magic_link, token)).to be_nil
    end

    it 'ignores magic links for deactivated users' do
      user = create(:user, :deactivated)
      expect(User.find_active_by_token_for(:magic_link, user.generate_token_for(:magic_link))).to be_nil
    end
  end

  it 'signs out everywhere when deactivated' do
    user = create(:user)
    user.user_sessions.create!
    user.deactivate!
    expect(user.user_sessions.reload).to be_empty
  end
end
