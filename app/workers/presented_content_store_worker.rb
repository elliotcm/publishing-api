class PresentedContentStoreWorker
  attr_reader :params
  include Sidekiq::Worker
  include PerformAsyncInQueue

  HIGH_QUEUE = "content_store_high".freeze
  LOW_QUEUE = "content_store_low".freeze

  sidekiq_options queue: HIGH_QUEUE

  def perform(args = {})
    assign_attributes(args.deep_symbolize_keys)

    broadcast_to_message_queue if params[:broadcast]

    update_content_store
  end

private

  def broadcast_to_message_queue
    # @todo Maybe throw exception - pain point of the shoehorning of message queue
    return unless content_item_id
    payload = Presenters::MessageQueuePresenter.present(
      content_item,
      state_fallback_order: [:published],
      update_type: broadcast_update_type,
    )

    PublishingAPI.service(:queue_publisher).send_message(payload)
  end

  def update_content_store
    if params[:delete]
      delete_from_content_store
    else
      send_to_content_store
    end

    enqueue_dependencies
  rescue => e
    handle_error(e)
  end

  def send_to_content_store
    if content_item_id
      content_store_is_live = (content_store == Adapters::ContentStore)

      if content_store_is_live
        if State.where(content_item_id: content_item_id).pluck(:name) == ["draft"]
          raise CommandError.new(
            code: 500,
            message: "Will not send a draft content item to the live content store",
          )
        end
      end

      base_path = presented_payload.fetch(:base_path)
      content_store.put_content_item(base_path, presented_payload)
    else
      base_path = payload.fetch(:base_path)
      content_store.put_content_item(base_path, payload)
    end
  end

  def presented_payload
    Presenters::ContentStorePresenter.present(content_item, payload_version, state_fallback_order: content_store::DEPENDENCY_FALLBACK_ORDER)
  end

  def payload_version
    payload.fetch(:payload_version)
  end

  def delete_from_content_store
    base_path = params.fetch(:base_path)
    content_store.delete_content_item(base_path)
  end

  def content_store
    params.fetch(:content_store).constantize
  end

  def assign_attributes(params)
    @params = params
  end

  def payload
    params.fetch(:payload, {})
  end

  def content_item_id
    payload[:content_item_id] || payload[:content_item]
  end

  def content_item
    @content_item ||= ContentItem.find(content_item_id)
  end

  def enqueue_dependency_check?
    params.fetch(:enqueue_dependency_check, true)
  end

  def broadcast_update_type
    payload[:broadcast_update_type] || content_item.update_type
  end

  def enqueue_dependencies
    return unless content_item_id
    return unless enqueue_dependency_check?
    DependencyResolutionWorker.perform_async(
      content_store: content_store,
      fields: presented_payload.keys,
      content_id: content_item.content_id,
      payload_version: payload_version,
    )
  end

  def handle_error(error)
    if !error.is_a?(CommandError)
      raise error
    elsif error.code >= 500
      raise error
    else
      explanation = "The message is a duplicate and does not need to be retried"
      Airbrake.notify_or_ignore(error, parameters: { explanation: explanation })
    end
  end
end
