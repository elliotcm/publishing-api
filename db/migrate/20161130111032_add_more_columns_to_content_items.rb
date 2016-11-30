class AddMoreColumnsToContentItems < ActiveRecord::Migration[5.0]
  def change
    add_column :content_items, :user_facing_version, :integer
    add_column :content_items, :locale, :string
    # execute(
    #   UPDATE content_items set user_facing_version = (select user_facing_versions.number from user_facing_versions where user_facing_versions.content_item_id = content_items.id);
    # )
    # execute(
    #   UPDATE content_items set locale = (select translations.locale from translations where translations.content_item_id = content_items.id);
    # )
  end
end
