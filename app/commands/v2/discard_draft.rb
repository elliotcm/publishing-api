module Commands
  module V2
    class DiscardDraft < BaseCommand
      def call
        raise_error_if_missing_draft!

        check_version_and_raise_if_conflicting(draft, payload[:previous_version])

        draft_path = Location.find_by!(content_item: draft).base_path
        delete_supporting_objects

        if live
          increment_live_lock_version
        else
          delete_draft_from_database
          delete_draft_from_draft_content_store(draft_path) if downstream
        end

        Success.new(content_id: content_id)
      end

    private
      def raise_error_if_missing_draft!
        return if draft.present?

        code = live.present? ? 422 : 404
        message = "There is no draft content item to discard"

        raise CommandError.new(code: code, message: message)
      end

      def delete_draft_from_database
        draft.destroy
      end

      def delete_draft_from_draft_content_store(draft_path)
        ContentStoreWorker.perform_async(
          content_store: Adapters::DraftContentStore,
          base_path: draft_path,
          delete: true,
        )
      end

      def delete_supporting_objects
        State.find_by(content_item: draft).try(:destroy)
        Translation.find_by(content_item: draft).try(:destroy)
        Location.find_by(content_item: draft).try(:destroy)
        SemanticVersion.find_by(content_item: draft).try(:destroy)
        Version.find_by(target: draft).try(:destroy)
        AccessLimit.find_by(content_item: draft).try(:destroy)
      end

      def increment_live_lock_version
        lock_version = Version.find_by!(target: live)
        lock_version.increment
        lock_version.save!
      end

      def draft
        @draft ||= ContentItemFilter.new(scope: ContentItem.where(content_id: content_id)).filter(
          locale: locale,
          state: "draft",
        ).first
      end

      def live
        @live ||= ContentItemFilter.new(scope: ContentItem.where(content_id: content_id)).filter(
          locale: locale,
          state: "published",
        ).first
      end

      def content_id
        payload[:content_id]
      end

      def locale
        payload[:locale] || ContentItem::DEFAULT_LOCALE
      end
    end
  end
end
