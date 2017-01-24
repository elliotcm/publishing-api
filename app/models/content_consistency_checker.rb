class ContentConsistencyChecker
  attr_reader :content_id

  def initialize(content_id)
    @content_id = content_id
    @errors = []
  end

  def call
    redirects.each do |redirect|
      check_item_redirect(redirect)
    end

    routes.each do |route|
      path = route["path"]

      check_item_route(route)

      next unless (content_store_item = item_from_content_store(path))

      if state == "gone"
        @errors << "content-store: State is gone but the content exists in a " \
                   "content store."
      end

      if state == "gone" && handler != "gone"
        @errors << "router: State claims to be gone but handler is not."
      end

      if (%w(published draft).include? state) && handler != "backend"
        @errors << "router: State is published or draft but handler " \
                   "is not backend."
      end

      unless state == "gone"
        if content_store_item["rendering_app"] != rendering_app
          @errors << "content-store: Rendering app " \
                     "(#{content_store_item["rendering_app"]}) does not " \
                     "match backend_id (#{rendering_app})."
        end
      end
    end

    @errors
  end

private

  def content_store
    state == "published" ? live_content_store : draft_content_store
  end

  def item_from_content_store(path)
    begin
      content_store.content_item(path).parsed_content
    rescue GdsApi::ContentStore::ItemNotFound
      @errors << "content-store: State is published but the content is not " \
        "in live content store."
    rescue GdsApi::HTTPForbidden
      @errors << "content-store: HTTP 403 response."
    end
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

    if res["route_type"] != redirect["type"]
      @errors << "router-api: Route type (#{res["route_type"]}) does not " \
                 "match item route type (#{redirect["type"]})."
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

    if res["route_type"] != route["type"]
      @errors << "router-api: Route type (#{res["route_type"]}) does not " \
                 "match item route type (#{route["type"]})."
    end

    if res["backend_id"] != backend_id
      @errors << "router-api: Backend ID (#{res["backend_id"]}) does not " \
                 "match item backend (#{backend_id})."
    end

    if res["disabled"]
      @errors << "router-api: Item is marked as disabled."
    end

    if res["handler"] != handler
      @errors << "router-api: Handler (#{res["handler"]}) does not match " \
                 "item handler (#{handler})."
    end
  end

  def item
    @item ||= Queries::GetContent.(content_id)
  end

  def backend_id
    item["rendering_app"]
  end

  def state
    item["publication_state"]
  end

  def handler
    %w(published superseded unpublished).include?(state) ? "backend" : state
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
