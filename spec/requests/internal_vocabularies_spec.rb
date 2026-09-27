require 'rails_helper'

RSpec.describe "Internal::Vocabularies", type: :request do
  before { sign_in_as create(:user) }

  it "shows the shared list with the team names it pulls in" do
    create(:team, name: "Richland", slug: "richland")
    create(:vocabulary, phrases: "DAC Sports")

    get internal_vocabulary_path

    expect(response.body).to include("DAC Sports", "Richland", "Thunderducks")
  end

  it "saves the phrases and queues the Mux sync" do
    patch internal_vocabulary_path, params: { vocabulary: { phrases: "DAC Sports\nDallas College" } }

    expect(response).to redirect_to(internal_vocabulary_path)
    expect(Vocabulary.global.phrase_list).to eq([ "DAC Sports", "Dallas College" ])
    expect(SyncVocabularyJob.jobs.size).to eq(1)
  end
end
