require 'gds_api/content_store'
require 'gds_api/router'

class ContentConsistencyChecker
  attr_reader :content_id

  def initialize(content_id)
    @content_id = content_id
    @errors = []
  end

  def call
    return @errors unless item

    redirects.each do |redirect|
      check_item_redirect(redirect)
    end

    routes.each do |route|
      path = route["path"]

      check_item_route(route)

      next unless (content_store_item = item_from_content_store(path))

      if document_type == "gone" || schema_name == "gone"
        @errors << "content-store: State is gone but the content exists in a " \
                   "content store."
      end

      if content_store_item["rendering_app"] != rendering_app
        @errors << "content-store: Rendering app " \
                   "(#{content_store_item["rendering_app"]}) does not " \
                   "match item rendering app (#{rendering_app})."
      end
    end

    @errors
  end

private

  def content_store
    item["content_store"] == "live" ? live_content_store : draft_content_store
  end

  def item_from_content_store(path)
    begin
      return content_store.content_item(path).parsed_content
    rescue GdsApi::ContentStore::ItemNotFound
      @errors << "content-store: State is published but the content is not " \
        "in live content store."
    rescue GdsApi::HTTPForbidden
      @errors << "content-store: HTTP 403 response."
    end
    nil
  end

  def check_item_redirect(redirect)
    path = redirect["path"]

    begin
      res = router_api.get_route(path).parsed_content
    rescue GdsApi::HTTPNotFound
      @errors << "router-api: Path (#{path}) was not found!"
      return
    end

    if res["handler"] != "redirect"
      @errors << "router-api: Handler is not a redirect for #{path}."
    end

    if res["redirect_to"] != redirect["destination"]
      @errors << "router-api: Route destination (#{res["redirect_to"]}) " \
                 "does not match item destination (#{redirect["destination"]})."
    end
  end

  def check_item_route(route)
    return if state == "draft"

    path = route["path"]

    begin
      res = router_api.get_route(path).parsed_content
    rescue GdsApi::HTTPNotFound
      @errors << "router-api: Path (#{path}) was not found!"
      return
    end

    if res["handler"] != expected_handler
      @errors << "router-api: Handler (#{res["handler"]}) does not match " \
                 "expected item handler (#{expected_handler})."
    end

    if res["backend_id"] != rendering_app
      @errors << "router-api: Backend ID (#{res["backend_id"]}) does not " \
                 "match item rendering app (#{rendering_app})."
    end

    if res["disabled"]
      @errors << "router-api: Item is marked as disabled."
    end
  end

  def item
    @item ||= Queries::GetContent.(content_id)
  rescue CommandError
    @errors << "publishing-api: Content (#{content_id}) could not be found."
    @item ||= nil
  end

  def document_type
    item["document_type"]
  end

  def schema_name
    item["schema_name"]
  end

  def state
    item["publication_state"]
  end

  def expected_handler
    if redirects.any?
      "redirect"
    elsif rendering_app.nil?
      "gone"
    else
      "backend"
    end
  end

  def redirects
    item["redirects"]
  end

  def routes
    item["routes"]
  end

  def rendering_app
    item["rendering_app"]
  end

  def router_api
    GdsApi::Router.new(Plek.find('router-api'))
  end

  def live_content_store
    GdsApi::ContentStore.new(Plek.find('content-store'))
  end

  def draft_content_store
    GdsApi::ContentStore.new(Plek.find('draft-content-store'))
  end
end
