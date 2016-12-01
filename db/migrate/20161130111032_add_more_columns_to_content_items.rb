class AddMoreColumnsToContentItems < ActiveRecord::Migration[5.0]
  def change
    add_column :content_items, :user_facing_version, :integer
    add_column :content_items, :locale, :string
    add_column :content_items, :latest_version, :boolean, default: false
    execute(
      "UPDATE content_items set user_facing_version = (select user_facing_versions.number from user_facing_versions where user_facing_versions.content_item_id = content_items.id)"
    )
    execute(
      "UPDATE content_items set locale = (select translations.locale from translations where translations.content_item_id = content_items.id)"
    )
    execute(
      <<-SQL
      update content_items set latest_version = true
      where content_items.id in (
      select la.id from content_items join (
        select id, max(user_facing_version) over(partition by content_id, locale) as latest_version, locale from content_items) la
      on la.id = content_items.id and la.locale = content_items.locale and la.latest_version = content_items.user_facing_version
      )
      SQL
    )
    add_index :content_items :latest_version
    add_index :content_items [:document_type, :latest_version]
  end
end
