class SyncVocabularyJob
  include Sidekiq::Job

  def perform(vocabulary_id)
    Vocabulary.find_by(id: vocabulary_id)&.sync_to_mux!
  end
end
