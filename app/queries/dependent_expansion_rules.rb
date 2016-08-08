module Queries
  module DependentExpansionRules
    extend self

    def expansion_fields(link_type)
      custom(link_type) || default_fields
    end

    def recurse?(link_type)
      recursive_link_types.include?(link_type.to_sym)
    end

    def reverse_name_for(link_type)
      {
        parent: "children",
        documents: "document_collections",
        working_groups: 'policies'
      }[link_type.to_sym]
    end

    def recursive_link_types
      [:parent]
    end

  private

    def custom(link_type)
      {}[link_type]
    end

    def default_fields
      [
        :analytics_identifier,
        :api_url,
        :base_path,
        :content_id,
        :description,
        :document_type,
        :locale,
        :public_updated_at,
        :schema_name,
        :title,
        :web_url
      ]
    end
  end
end
