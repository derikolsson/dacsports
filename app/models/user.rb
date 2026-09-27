class User < ApplicationRecord
  MINIMUM_PASSWORD_LENGTH = 12

  # Invitees have no password until they accept, so we supply our own validations.
  has_secure_password validations: false

  has_many :user_sessions, dependent: :destroy
  has_many :passkeys, dependent: :destroy
  belongs_to :invited_by, class_name: "User", optional: true

  normalizes :email_address, with: ->(email) { email.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: MINIMUM_PASSWORD_LENGTH, maximum: ActiveModel::SecurePassword::MAX_PASSWORD_LENGTH_ALLOWED }, allow_nil: true
  validates :password, confirmation: true, allow_nil: true
  validates :password_digest, presence: { message: "can't be blank" }, if: :invitation_accepted?

  before_validation(on: :create) { self.webauthn_id ||= WebAuthn.generate_user_id }

  scope :active, -> { where(deactivated_at: nil).where.not(invitation_accepted_at: nil) }
  scope :pending, -> { where(deactivated_at: nil, invitation_accepted_at: nil) }

  # Both die once used: accepting stamps invitation_accepted_at, signing in bumps last_signed_in_at.
  generates_token_for :invitation, expires_in: 7.days do
    invitation_accepted_at
  end

  generates_token_for :magic_link, expires_in: 15.minutes do
    last_signed_in_at
  end

  def self.authenticate(email_address:, password:)
    user = authenticate_by(email_address: email_address, password: password)
    user if user&.active?
  end

  def self.find_active_by_token_for(purpose, token)
    user = find_by_token_for(purpose, token)
    user if user&.active?
  end

  def invitation_accepted?
    invitation_accepted_at.present?
  end

  def pending?
    !invitation_accepted? && !deactivated?
  end

  def deactivated?
    deactivated_at.present?
  end

  def active?
    invitation_accepted? && !deactivated?
  end

  def accept_invitation(name:, password:, password_confirmation:)
    self.name = name
    self.password = password.presence
    self.password_confirmation = password_confirmation
    self.invitation_accepted_at = Time.current
    save.tap { |saved| self.invitation_accepted_at = nil unless saved }
  end

  def deactivate!
    transaction do
      update!(deactivated_at: Time.current)
      user_sessions.destroy_all
    end
  end

  def display_name
    name.presence || email_address
  end
end
