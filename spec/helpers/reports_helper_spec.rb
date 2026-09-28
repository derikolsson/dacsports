require 'rails_helper'

RSpec.describe ReportsHelper do
  describe '#period_change' do
    it 'shows growth against the previous figure' do
      expect(helper.period_change(150, 100)).to include("▲ 50%", "vs 100 previous period", "text-success")
    end

    it 'shows a decline' do
      expect(helper.period_change(75, 100)).to include("▼ 25%", "text-danger")
    end

    it 'calls growth from nothing new rather than infinite' do
      expect(helper.period_change(5, 0)).to include("New")
    end

    it 'shows nothing without a previous period' do
      expect(helper.period_change(5, nil)).to be_nil
    end
  end
end
