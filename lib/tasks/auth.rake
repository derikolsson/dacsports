namespace :auth do
  desc "Invite an admin by email and print the invitation link (for the first admin, or when mail isn't working)"
  task :invite, [ :email ] => :environment do |_task, args|
    abort "Usage: bin/rails \"auth:invite[someone@example.com]\"" if args[:email].blank?

    user = User.find_or_initialize_by(email_address: args[:email])
    abort "#{user.email_address} already has an account." if user.persisted? && !user.pending?

    user.admin = true
    user.save!
    AuthMailer.invitation(user).deliver_later

    url = Rails.application.routes.url_helpers.internal_invitation_url(
      user.generate_token_for(:invitation), **Rails.application.config.action_mailer.default_url_options
    )
    puts "Invitation emailed to #{user.email_address}. The link, which expires in 7 days:"
    puts url
  end
end
