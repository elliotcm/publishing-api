require 'rails_helper'

RSpec.describe Presenters::Queries::ContentItemPresenter do
  let(:content_id) { SecureRandom.uuid }
  let(:base_path) { "/vat-rates" }

  describe "present" do
    let!(:content_item) do
      FactoryGirl.create(:draft_content_item,
        content_id: content_id,
        base_path: base_path
      )
    end

    let(:result) { described_class.present(content_item) }

    let(:payload) do
      {
        "content_id" => content_id,
        "locale" => "en",
        "base_path" => base_path,
        "title" => "VAT rates",
        "document_type" => "guide",
        "schema_name" => "guide",
        "public_updated_at" => "2014-05-14T13:00:06Z",
        "last_edited_at" => "2014-05-14T13:00:06Z",
        "first_published_at" => "2014-01-02T03:04:05Z",
        "details" => { "body" => "<p>Something about VAT</p>\n" },
        "routes" => [{ "path" => base_path, "type" => "exact" }],
        "redirects" => [],
        "publishing_app" => "publisher",
        "rendering_app" => "frontend",
        "need_ids" => %w(100123 100124),
        "update_type" => "minor",
        "phase" => "beta",
        "analytics_identifier" => "GDS01",
        "description" => "VAT rates for goods and services",
        "publication_state" => "draft",
        "user_facing_version" => 1,
        "lock_version" => 1,
        "updated_at" => "2016-01-01 00:00:00",
        "state_history" => { 1 => "draft" },
      }
    end

    around do |example|
      Timecop.freeze(Date.new(2016, 1, 1)) do
        example.run
      end
    end

    it "presents content item attributes as a hash" do
      expect(result).to eq(payload)
    end

    context "for a draft content item" do
      it "has a publication state of draft" do
        expect(result.fetch("publication_state")).to eq("draft")
      end
    end

    context "for a published content item" do
      before do
        content_item.update_attributes!(state: 'published')
      end

      it "has a publication state of published" do
        expect(result.fetch("publication_state")).to eq("published")
      end
    end

    context "when the content item exists in multiple locales" do
      let!(:french_item) do
        FactoryGirl.create(:draft_content_item, content_id: content_id, locale: "fr")
      end

      it "presents the item with matching locale" do
        result = described_class.present(french_item)
        expect(result.fetch("locale")).to eq("fr")

        result = described_class.present(content_item)
        expect(result.fetch("locale")).to eq("en")
      end
    end

    context "when a change note exists" do
      let!(:content_item) do
        FactoryGirl.create(:draft_content_item,
          content_id: content_id,
          base_path: base_path,
          update_type: "major"
        )
      end

      it "presents the item including the change note" do
        expected = payload.merge(
          "change_note" => "note",
          "update_type" => "major"
        )
        expect(result).to eq expected
      end
    end
  end

  describe "#present_many" do
    let!(:content_item) do
      FactoryGirl.create(:draft_content_item,
        content_id: content_id,
      )
    end

    context "when an array of fields is provided" do
      let(:fields) { %w(title phase publication_state) }

      it "returns the requested fields" do
        content_items = ContentItem.where(content_id: content_id)

        results = described_class.present_many(content_items, fields: fields)
        expect(results.first.keys).to match_array(%w(title phase publication_state))
      end
    end

    context "when the content item exists in multiple locales" do
      let!(:french_item) do
        FactoryGirl.create(:content_item, content_id: content_id, locale: "fr")
      end

      it "presents a content item for each locale" do
        content_items = ContentItem.where(content_id: content_id)

        results = described_class.present_many(content_items)
        locales = results.map { |r| r.fetch("locale") }

        expect(locales).to match_array(%w(fr en))
      end
    end

    context "when there are other content items with that content_id" do
      before do
        content_item.update_attributes(user_facing_version: 2)
      end

      let!(:published_item) do
        FactoryGirl.create(
          :live_content_item,
          content_id: content_id,
          user_facing_version: 1,
        )
      end

      let(:content_items) { ContentItem.where(content_id: content_id) }

      it "returns a versioned history of states for the content item" do
        results = described_class.present_many(content_items)
        expect(results.count).to eq(1)

        state_history = results.first.fetch("state_history")
        expect(state_history).to eq(
          1 => "published",
          2 => "draft"
        )
      end
    end
  end

  describe "#get_warnings" do
    before do
      FactoryGirl.create(:draft_content_item,
        content_id: content_id,
        base_path: base_path,
        user_facing_version: 2,
      )
    end

    let(:scope) do
      ContentItem.where(content_id: content_id)
    end

    context "when include_warnings is false" do
      let(:result) do
        described_class.present_many(scope, include_warnings: false)
      end

      it "does not include warnings" do
        expect(result.first.key?("warnings")).to be false
      end
    end

    context "when include_warnings is true" do
      let(:result) do
        described_class.present_many(scope, include_warnings: true)
      end

      context "without a blocking content item" do
        it "does not include warnings" do
          expect(result.first["warnings"]).to be_empty
        end
      end

      context "with a blocking content item" do
        before do
          @blocking_content_item = FactoryGirl.create(:live_content_item,
            content_id: SecureRandom.uuid,
            base_path: base_path,
            user_facing_version: 1,
            locale: "en",
          )
        end

        it "includes the warning" do
          expect(result.first["warnings"]).to have_key(
            "content_item_blocking_publish"
          )
        end
      end

      context "when a required field is omitted" do
        it "raises an error" do
          expect {
            described_class.present_many(
              scope,
              include_warnings: true,
              fields: described_class::DEFAULT_FIELDS - [:base_path],
            ).first
          }.to raise_error(/must be included/)
        end
      end
    end
  end
end
