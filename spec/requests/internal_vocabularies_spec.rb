require 'rails_helper'

RSpec.describe "Internal::Vocabularies", type: :request do
  let(:credentials) { Rails.application.credentials.internal_auth || {} }
  let(:auth_headers) do
    {
      "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(
        credentials[:username], credentials[:password]
      )
    }
  end

  it "requires authentication" do
    get internal_vocabulary_path
    expect(response).to have_http_status(:unauthorized)
  end

  it "shows the shared list with the team names it pulls in" do
    create(:team, name: "Richland", slug: "richland")
    create(:vocabulary, phrases: "DAC Sports")

    get internal_vocabulary_path, headers: auth_headers

    expect(response.body).to include("DAC Sports", "Richland", "Thunderducks")
  end

  it "saves the phrases and queues the Mux sync" do
    patch internal_vocabulary_path, params: { vocabulary: { phrases: "DAC Sports\nDallas College" } }, headers: auth_headers

    expect(response).to redirect_to(internal_vocabulary_path)
    expect(Vocabulary.global.phrase_list).to eq([ "DAC Sports", "Dallas College" ])
    expect(SyncVocabularyJob.jobs.size).to eq(1)
  end
end
