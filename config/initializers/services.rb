module PublishingAPI
  # To be set in dev mode so that this can run when the draft content store isn't running.
  cattr_accessor :swallow_connection_errors

  def self.register_service(name:, client:)
    @services ||= {}

    @services[name] = client
  end

  def self.service(name)
    @services[name] || raise(ServiceNotRegisteredException.new(name))
  end

  class ServiceNotRegisteredException < Exception; end
end

PublishingAPI.register_service(
  name: :draft_content_store,
  client: ContentStoreWriter.new(Plek.find('draft-content-store'))
)

PublishingAPI.register_service(
  name: :live_content_store,
  client: ContentStoreWriter.new(Plek.find('content-store'))
)

if ENV['DISABLE_QUEUE_PUBLISHER'] || (Rails.env.test? && ENV['ENABLE_QUEUE_IN_TEST_MODE'].blank?)
  rabbitmq_config = { noop: true }
else
  rabbitmq_config = YAML.load_file(Rails.root.join("config", "rabbitmq.yml"))[Rails.env].symbolize_keys
end

PublishingAPI.register_service(
  name: :queue_publisher,
  client: QueuePublisher.new(rabbitmq_config)
)

if Rails.env.development?
  PublishingAPI.swallow_connection_errors = true
end

# Statsd "the process" listens on a port on the provided host for UDP
# messages. Given that it's UDP, it's fire-and-forget and will not
# block your application. You do not need to have a statsd process
# running locally on your development environment.
statsd_client = Statsd.new("localhost")
statsd_client.namespace = "govuk.app.publishing-api"
PublishingAPI.register_service(name: :statsd, client: statsd_client)
AsyncExperiments.statsd = statsd_client
