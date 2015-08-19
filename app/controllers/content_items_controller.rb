class ContentItemsController < ApplicationController
  include URLArbitration

  before_filter :parse_content_item
  before_filter :validate_routing_key_fields, only: [:put_live_content_item]

  def put_live_content_item
    notify_prototype(live_actions)

    with_url_arbitration do
      with_502_suppression do
        draft_content_store.put_content_item(
          base_path: base_path,
          content_item: content_item_without_access_limiting,
        )
      end

      live_response = live_content_store.put_content_item(
        base_path: base_path,
        content_item: content_item_without_access_limiting,
      )

      queue_publisher.send_message(content_item_with_base_path)

      render json: content_item_without_access_limiting,
             content_type: live_response.headers[:content_type]
    end
  end

  def put_draft_content_item
    notify_prototype(draft_actions)

    with_url_arbitration do
      draft_response = with_502_suppression do
        draft_content_store.put_content_item(
          base_path: base_path,
          content_item: content_item,
        )
      end

      if draft_response
        render json: content_item, content_type: draft_response.headers[:content_type]
      else
        render json: content_item
      end
    end
  end

private

  def with_502_suppression(&block)
    block.call
  rescue GdsApi::HTTPServerError => e
    unless e.code == 502 && ENV["SUPPRESS_DRAFT_STORE_502_ERROR"]
      raise e
    end
  end

  def draft_content_store
    PublishingAPI.services(:draft_content_store)
  end

  def live_content_store
    PublishingAPI.services(:live_content_store)
  end

  def queue_publisher
    PublishingAPI.services(:queue_publisher)
  end

  def content_item_without_access_limiting
    @content_item_without_access_limiting ||= content_item.except(:access_limited)
  end

  def content_item_with_base_path
    content_item_without_access_limiting.merge(base_path: base_path)
  end

  def validate_routing_key_fields
    unless [:format, :update_type].all? {|field| content_item[field] =~ /\A[a-z0-9_]+\z/i}
      head :unprocessable_entity
    end
  end

  def notify_prototype(workflow_actions)
    RestClient.post("http://localhost:4000/api/content-items", {
        content_item: {
          id: content_item[:content_id],
          workflow_actions: workflow_actions
        }
      }.to_json,
      content_type: :json,
      accept: :json
    )
  end

  def draft_actions
    {
      draft_content_store: {
        state: "incomplete",
        human_action: "Sending to draft GOV.UK",
      },
    }
  end

  def live_actions
    draft_actions.merge(
      live_content_store: {
        state: "incomplete",
        human_action: "Sending to live GOV.UK",
      },
      message_bus: {
        state: "incomplete",
        human_action: "Sending emails",
      }
    )
  end
end
