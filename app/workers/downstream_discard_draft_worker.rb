class DownstreamDiscardDraftWorker
  include DownstreamQueue
  include Sidekiq::Worker
  include PerformAsyncInQueue

  sidekiq_options queue: HIGH_QUEUE

  def perform(args = {})
    assign_attributes(args.symbolize_keys)

    current_path = web_content_item.try(:base_path)
    if current_path
      DownstreamService.update_draft_content_store(
        DownstreamPayload.new(web_content_item, payload_version, Adapters::ContentStore::DEPENDENCY_FALLBACK_ORDER)
      )
      if base_path && current_path != base_path
        DownstreamService.discard_from_draft_content_store(base_path)
      end
    elsif base_path
      DownstreamService.discard_from_draft_content_store(base_path)
    end

    enqueue_dependencies if update_dependencies
  rescue DiscardDraftBasePathConflictError => e
    alert_on_base_path_conflict ? notify_airbrake(e, args) : logger.warn(e.message)
  end

private

  attr_reader :base_path, :content_id, :locale, :web_content_item,
    :payload_version, :update_dependencies, :alert_on_base_path_conflict

  def assign_attributes(attributes)
    @base_path = attributes.fetch(:base_path)
    @content_id = attributes.fetch(:content_id)
    assign_backwards_compatible_content_item(attributes)
    @payload_version = attributes.fetch(:payload_version)
    @update_dependencies = attributes.fetch(:update_dependencies, true)
    @alert_on_base_path_conflict = attributes.fetch(:alert_on_base_path_conflict, true)
  end

  def assign_backwards_compatible_content_item(attributes)
    if attributes[:locale]
      @locale = attributes[:locale]
      @web_content_item = Queries::GetWebContentItems.for_content_store(content_id, locale, true)
    else
      content_item_id = attributes[:live_content_item_id]
      @web_content_item = content_item_id ? Queries::GetWebContentItems.find(content_item_id) : nil
      @locale = web_content_item.try(:locale)
    end
  end

  def enqueue_dependencies
    DependencyResolutionWorker.perform_async(
      content_store: Adapters::DraftContentStore,
      fields: [:content_id],
      content_id: content_id,
      payload_version: payload_version,
    )
  end

  def notify_airbrake(error, parameters)
    Airbrake.notify(error, parameters: parameters)
  end
end
