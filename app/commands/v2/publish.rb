module Commands
  module V2
    class Publish < BaseCommand
      def call
        validate

        publish_content_item

        after_transaction_commit do
          send_downstream(content_item.content_id, content_item.locale, update_type)
        end

        Success.new(content_id: content_id)
      end

    private

      def publish_content_item
        delete_change_notes unless update_type == "major"
        previous_item.supersede if previous_item

        unless content_item.pathless?
          redirect_old_base_path
          clear_published_items_of_same_locale_and_base_path
        end

        set_public_updated_at
        set_first_published_at
        content_item.publish
        remove_access_limit
        create_publish_action
      end

      def create_publish_action
        Action.create_publish_action(content_item, locale, event)
      end

      def remove_access_limit
        AccessLimit.find_by(content_item: content_item).try(:destroy)
      end

      def validate
        no_draft_item_exists unless content_item
        validate_update_type
        check_version_and_raise_if_conflicting(content_item, previous_version_number)
      end

      def update_type
        @update_type ||= payload[:update_type] || content_item.update_type
      end

      def previous_item
        @previous_item ||= lookup_previous_item
      end

      def redirect_old_base_path
        return unless previous_item
        previous_base_path = previous_item.base_path

        if previous_base_path != content_item.base_path
          publish_redirect(previous_base_path, content_item.locale)
        end
      end

      def no_draft_item_exists
        if already_published?
          message = "Cannot publish an already published content item"
          raise_command_error(400, message, fields: {})
        else
          message = "Item with content_id #{content_id} and locale #{locale} does not exist"
          raise_command_error(404, message, fields: {})
        end
      end

      def validate_update_type
        if update_type.blank?
          raise_command_error(422, "update_type is required", fields: {
            update_type: ["is invalid"],
          })
        elsif !valid_update_types.include?(update_type)
          raise_command_error(422, "An update_type of '#{update_type}' is invalid", fields: {
            update_type: ["must be one of #{valid_update_types.inspect}"],
          })
        end
      end

      def delete_change_notes
        ChangeNote.where(content_item: content_item).delete_all
      end

      def content_id
        payload[:content_id]
      end

      def locale
        payload.fetch(:locale, ContentItem::DEFAULT_LOCALE)
      end

      def previous_version_number
        payload[:previous_version].to_i if payload[:previous_version]
      end

      def valid_update_types
        %w(major minor republish links)
      end

      def content_item
        @content_item ||= ContentItem.find_by(
          id: pessimistic_content_item_scope.pluck(:id),
          state: "draft",
        )
      end

      def already_published?
        ContentItem.exists?(content_id: content_id, locale: locale, state: "published")
      end

      def pessimistic_content_item_scope
        ContentItem.where(content_id: content_id, locale: locale).lock
      end

      def clear_published_items_of_same_locale_and_base_path
        SubstitutionHelper.clear!(
          new_item_document_type: content_item.document_type,
          new_item_content_id: content_item.content_id,
          state: "published",
          locale: content_item.locale,
          base_path: content_item.base_path,
          downstream: downstream,
          callbacks: callbacks,
          nested: true,
        )
      end

      def set_public_updated_at
        return if content_item.public_updated_at.present?

        if update_type == "major"
          content_item.update_attributes!(public_updated_at: Time.zone.now)
        elsif update_type == "minor"
          content_item.update_attributes!(public_updated_at: previous_item.public_updated_at)
        end
      end

      def set_first_published_at
        return if content_item.first_published_at.present?
        content_item.update_attributes!(first_published_at: Time.zone.now)
      end

      def publish_redirect(previous_base_path, locale)
        draft_redirect = ContentItem.find_by(
          state: "draft",
          locale: locale,
          base_path: previous_base_path,
          schema_name: "redirect",
        )

        self.class.call(
          {
            content_id: draft_redirect.content_id,
            locale: locale,
            update_type: "major",
          },
          downstream: downstream,
          callbacks: callbacks,
          nested: true,
        ) if draft_redirect
      end

      def lookup_previous_item
        previous_items = ContentItem.where(
          content_id: content_id,
          locale: locale,
          state: %w(published unpublished),
        )

        if previous_items.size > 1
          raise "There should only be one previous published or unpublished item"
        end

        previous_items.order("content_id").first
      end

      def send_downstream(content_id, locale, update_type)
        return unless downstream

        queue = update_type == 'republish' ? DownstreamLiveWorker::LOW_QUEUE : DownstreamLiveWorker::HIGH_QUEUE

        DownstreamLiveWorker.perform_async_in_queue(
          queue,
          content_id: content_id,
          locale: locale,
          message_queue_update_type: update_type,
          payload_version: event.id,
        )
      end
    end
  end
end
