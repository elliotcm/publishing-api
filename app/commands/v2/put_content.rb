module Commands
  module V2
    class PutContent < BaseCommand
      def call
        validate_version_lock!

        content_item = create_or_update_draft_content_item!

        PathReservation.reserve_base_path!(base_path, content_item[:publishing_app])

        ContentStoreWorker.perform_async(
          content_store: Adapters::DraftContentStore,
          base_path: base_path,
          payload: draft_payload(content_item),
        )

        Success.new(payload)
      end

    private
      def validate_version_lock!
        super(DraftContentItem, content_id, payload[:previous_version])
      end

      def content_id
        payload.fetch(:content_id)
      end

      def create_or_update_draft_content_item!
        DraftContentItem.create_or_replace(content_item_attributes) do |item|
          version = Version.find_or_initialize_by(target: item)
          version.increment
          version.save! if item.valid?

          item.assign_attributes_with_defaults(content_item_attributes)
        end
      end

      def content_item_attributes
        payload.slice(*DraftContentItem::TOP_LEVEL_FIELDS)
      end

      def draft_payload(content_item)
        content_item_fields = DraftContentItem::TOP_LEVEL_FIELDS + [:links]
        draft_item_hash = LinkSetMerger.merge_links_into(content_item)
          .slice(*content_item_fields)

        Presenters::ContentItemPresenter.present(draft_item_hash)
      end
    end
  end
end