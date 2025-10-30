require 'rails_helper'

RSpec.describe EventSlug, type: :model do
  describe "associations" do
    it { should belong_to(:event) }
  end

  describe "validations" do
    subject { build(:event_slug) }

    it { should validate_presence_of(:slug) }
    it { should validate_presence_of(:event) }
    it { should validate_uniqueness_of(:slug) }
  end

  describe "database constraints" do
    it "enforces unique index on slug" do
      event = create(:event)
      create(:event_slug, event: event, slug: "unique-slug")

      expect {
        create(:event_slug, event: event, slug: "unique-slug")
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "prevents null slugs" do
      event_slug = build(:event_slug, slug: nil)
      expect(event_slug).not_to be_valid
      expect(event_slug.errors[:slug]).to include("can't be blank")
    end
  end

  describe "slug archival" do
    it "stores a valid slug format" do
      event_slug = create(:event_slug, slug: "valid-slug-123")
      expect(event_slug.slug).to eq("valid-slug-123")
    end

    it "can store multiple archived slugs for the same event" do
      event = create(:event, slug: "current-slug")
      slug1 = create(:event_slug, event: event, slug: "old-slug-1")
      slug2 = create(:event_slug, event: event, slug: "old-slug-2")

      expect(event.event_slugs).to include(slug1, slug2)
      expect(event.event_slugs.count).to eq(2)
    end

    it "can be used to find the current event" do
      event = create(:event, slug: "new-championship-game")
      archived_slug = create(:event_slug, event: event, slug: "old-championship-game")

      found_event = archived_slug.event
      expect(found_event).to eq(event)
      expect(found_event.slug).to eq("new-championship-game")
    end
  end

  describe "deletion" do
    it "is deleted when the event is deleted" do
      event = create(:event)
      event_slug = create(:event_slug, event: event)

      expect { event.destroy }.to change { EventSlug.count }.by(-1)
      expect(EventSlug.find_by(id: event_slug.id)).to be_nil
    end
  end

  describe "real-world scenarios" do
    context "when event title changes" do
      it "archives the old slug" do
        old_slug = create(:event_slug, :from_title_change)
        expect(old_slug.slug).to eq("old-game-title")
        expect(old_slug.event).to be_present
      end
    end

    context "when teams are updated" do
      it "archives the team-based slug" do
        old_slug = create(:event_slug, :from_team_change)
        expect(old_slug.slug).to eq("team-a-vs-team-b")
      end
    end

    context "when date changes in slug" do
      it "archives the date-based slug" do
        old_slug = create(:event_slug, :from_date_change)
        expect(old_slug.slug).to eq("championship-2024-01-15")
      end
    end
  end

  describe "lookup performance" do
    it "can quickly find archived slugs" do
      event = create(:event)
      create(:event_slug, event: event, slug: "findable-slug")

      expect(EventSlug.find_by(slug: "findable-slug")).to be_present
    end
  end
end
