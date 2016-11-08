require "rails_helper"

RSpec.describe DependencyResolutionWorker, :perform do
  let(:live_content_item) { FactoryGirl.create(:live_content_item, locale: "en") }

  subject(:worker_perform) do
    described_class.new.perform(content_id: "123",
                    fields: ["base_path"],
                    content_store: "Adapters::ContentStore",
                    payload_version: "123",
                   )
  end

  let(:content_item_dependee) { double(:content_item_dependent, call: []) }

  before do
    stub_request(:put, %r{.*content-store.*/content/.*})
    allow_any_instance_of(Queries::ContentDependencies).to receive(:call).and_return([live_content_item.content_id])
  end

  it "finds the content item dependees" do
    expect(Queries::ContentDependencies).to receive(:new).with(
      content_id: "123",
      fields: [:base_path],
      dependent_lookup: an_instance_of(Queries::GetDependents),
    ).and_return(content_item_dependee)
    worker_perform
  end

  it "the dependees get queued in the content store worker" do
    expect(DownstreamLiveWorker).to receive(:perform_async_in_queue).with(
      "downstream_low",
      a_hash_including(
        :content_id,
        :locale,
        :payload_version,
        message_queue_update_type: "links",
        update_dependencies: false,
      ),
    )
    worker_perform
  end

  context "with a draft version available" do
    let!(:draft_content_item) {
      FactoryGirl.create(:draft_content_item,
        content_id: live_content_item.content_id,
        locale: "en",
        user_facing_version: 2,
      )
    }

    it "doesn't send draft content to the live content store" do
      expect(DownstreamLiveWorker).to receive(:perform_async_in_queue).with(
        anything,
        a_hash_including(
          content_id: live_content_item.content_id,
          locale: "en",
        )
      )

      described_class.new.perform(
        content_id: "123",
        fields: ["base_path"],
        content_store: "Adapters::ContentStore",
        payload_version: "123",
      )
    end

    it "does send draft content to the draft content store" do
      expect(DownstreamDraftWorker).to receive(:perform_async_in_queue).with(
        anything,
        a_hash_including(
          content_id: draft_content_item.content_id,
          locale: "en",
        )
      )

      described_class.new.perform(
        content_id: "123",
        fields: ["base_path"],
        content_store: "Adapters::DraftContentStore",
        payload_version: "123",
      )
    end
  end
end
