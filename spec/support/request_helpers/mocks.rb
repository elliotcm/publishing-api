module RequestHelpers
  module Mocks
    extend self

    def api_path
      "/api/content" + base_path
    end

    def base_path
      "/vat-rates"
    end

    def content_id
      "582e1d3f-690e-4115-a948-e05b3c6b3d88"
    end

    def content_item_params
      {
        content_id: content_id,
        base_path: base_path,
        title: "VAT rates",
        description: "VAT rates for goods and services",
        document_type: "guide",
        schema_name: "guide",
        format: "guide",
        need_ids: %w(100123 100124),
        first_published_at: "2014-01-02T03:04:05Z",
        public_updated_at: "2014-05-14T13:00:06Z",
        publishing_app: "publisher",
        rendering_app: "frontend",
        locale: "en",
        phase: "beta",
        details: {
          body: "<p>Something about VAT</p>\n",
        },
        routes: [
          {
            path: base_path,
            type: "exact",
          }
        ],
        redirects: [],
        update_type: "major",
        analytics_identifier: "GDS01",
        expanded_links: {
          available_translations: available_translations
        }
      }
    end

    def access_limit_params
      {
        users: [
          "bf3e4b4f-f02d-4658-95a7-df7c74cd0f50",
          "74c7d700-5b4a-0131-7a8e-005056030037",
        ],
      }
    end

    def patch_links_attributes
      {
        content_id: content_id,
        links: {
          organisations: ["30986e26-f504-4e14-a93f-a9593c34a8d9"]
        }
      }
    end

    def available_translations
      [
        {
          analytics_identifier: "GDS01",
          api_path: "/api/content/vat-rates",
          base_path: "/vat-rates",
          content_id: content_id,
          description: "VAT rates for goods and services",
          schema_name: "guide",
          document_type: "guide",
          locale: "en",
          public_updated_at: DateTime.parse("2014-05-14T13:00:06Z"),
          title: "VAT rates",
          withdrawn: false,
        }
      ]
    end

    def redirect_content_item
      {
        base_path: "/crb-checks",
        document_type: "redirect",
        schema_name: "redirect",
        format: "redirect",
        public_updated_at: "2014-05-14T13:00:06Z",
        publishing_app: "publisher",
        redirects: [
          {
            path: "/crb-checks",
            type: "prefix",
            destination: "/dbs-checks"
          },
        ],
        update_type: "major",
      }
    end

    def v2_content_item
      content_item_params
        .except(:links)
        .merge(base_path: base_path)
    end
  end
end

RSpec.configuration.include RequestHelpers::Mocks, type: :request
