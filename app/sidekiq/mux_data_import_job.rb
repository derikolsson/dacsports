class MuxDataImportJob
  include Sidekiq::Job

  # Mux counts a view once it ends, so recent days keep filling in. Each run rebuilds
  # today and the three days before it.
  LOOKBACK_DAYS = 3

  def perform
    MuxDataImport.new.import((Date.current - LOOKBACK_DAYS)..Date.current)
  end
end
