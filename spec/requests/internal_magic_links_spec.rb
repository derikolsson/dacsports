require 'rails_helper'

RSpec.describe "Internal::MagicLinks", type: :request do
  let(:user) { create(:user, email_address: "coach@example.com") }

  it "emails a link to active users only, without revealing who has an account" do
    user
    expect { post internal_magic_links_path, params: { email_address: "Coach@example.com" } }
      .to have_enqueued_mail(AuthMailer, :magic_link)
    expect(response).to redirect_to(internal_login_path)

    expect { post internal_magic_links_path, params: { email_address: "nobody@example.com" } }
      .not_to have_enqueued_mail
    expect(response).to redirect_to(internal_login_path)
  end

  it "asks for a click before signing in, then works only once" do
    token = user.generate_token_for(:magic_link)

    get internal_magic_link_path(token)
    expect(response).to have_http_status(:ok)
    expect(user.user_sessions).to be_empty

    patch internal_magic_link_path(token)
    expect(response).to redirect_to(internal_root_url)

    delete internal_logout_path
    patch internal_magic_link_path(token)
    expect(response).to redirect_to(new_internal_magic_link_path)
  end

  it "expires after 15 minutes" do
    token = user.generate_token_for(:magic_link)
    travel 16.minutes do
      get internal_magic_link_path(token)
      expect(response).to redirect_to(new_internal_magic_link_path)
    end
  end
end
