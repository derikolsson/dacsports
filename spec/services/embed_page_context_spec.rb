require 'rails_helper'

RSpec.describe EmbedPageContext do
  let(:partner) { "https://northlake.example.edu" }

  def context(src:, title: "Live Athletics", ref: nil)
    described_class.from(src: src, title: title, ref: ref, partner_origin: partner)
  end

  it 'keeps the page, its title, the referrer origin and UTM tags' do
    result = context(src: "#{partner}/athletics/live?utm_source=newsletter&utm_campaign=homecoming&student=42#top",
                     ref: "https://www.facebook.com/some/post?id=1")

    expect(result).to eq(
      "page_url" => "#{partner}/athletics/live?utm_source=newsletter&utm_campaign=homecoming",
      "page_title" => "Live Athletics",
      "host_referrer_origin" => "https://www.facebook.com",
      "utm_source" => "newsletter",
      "utm_campaign" => "homecoming"
    )
  end

  # Anyone can put an iframe on their page with src= pointing at someone else's site.
  it 'ignores a page that is not on the partner origin' do
    expect(context(src: "https://someone-else.org/page")).to eq({})
  end

  it 'ignores everything without a partner origin to check against' do
    expect(described_class.from(src: "#{partner}/live", title: "x", ref: nil, partner_origin: nil)).to eq({})
  end

  it 'ignores a referrer that is the partner site itself' do
    expect(context(src: "#{partner}/live", ref: "#{partner}/schedule")).not_to have_key("host_referrer_origin")
  end

  it 'survives junk' do
    expect(context(src: "javascript:alert(1)")).to eq({})
    expect(context(src: "#{partner}/live", ref: "not a url at all ::")).to include("page_url" => "#{partner}/live")
  end

  it 'clips long values' do
    expect(context(src: "#{partner}/live", title: "x" * 1000)["page_title"].length).to eq(255)
  end
end
