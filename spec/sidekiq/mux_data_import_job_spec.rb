require 'rails_helper'

RSpec.describe MuxDataImportJob do
  include ActiveSupport::Testing::TimeHelpers

  it 'rebuilds today and the three days before it' do
    import = instance_double(MuxDataImport, import: nil)
    allow(MuxDataImport).to receive(:new).and_return(import)

    travel_to Time.zone.local(2026, 9, 29, 4) do
      described_class.new.perform
    end

    expect(import).to have_received(:import).with(Date.new(2026, 9, 26)..Date.new(2026, 9, 29))
  end
end
