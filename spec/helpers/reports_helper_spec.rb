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

  describe '#country_label' do
    it 'shows the flag and everyday name' do
      expect(helper.country_label("US")).to eq("🇺🇸 United States")
      expect(helper.country_label("KR")).to eq("🇰🇷 South Korea")
    end

    it 'keeps the code for a country without a name' do
      expect(helper.country_label("XK")).to eq("🇽🇰 XK")
    end

    it 'passes through anything that is not a country code' do
      expect(helper.country_label("Unknown")).to eq("Unknown")
    end
  end
end
