class LockVersion < ApplicationRecord
  belongs_to :target, polymorphic: true
  validate :numbers_must_increase

  after_save do
    item = lock_version_target
    next unless item
    item.update_column(:stale_lock_version, number) if number > (item.stale_lock_version || -1)
  end

  def self.join_content_items(content_item_scope)
    content_item_scope.joins(
      "INNER JOIN lock_versions ON
        lock_versions.target_id = content_items.id AND
        lock_versions.target_type = 'ContentItem'"
    )
  end

  def conflicts_with?(previous_version_number)
    return false if previous_version_number.nil?

    self.number != previous_version_number.to_i
  end

  def lock_version_target
    if content_item_target?
      target.document
    else
      target
    end
  end

  def increment
    self.number += 1
  end

  def increment!
    increment
    save!
  end

private

  def content_item_target?
    %w(ContentItem Edition).include? target_type
  end

  def numbers_must_increase
    return unless persisted?
    return unless number_changed? && number <= number_was

    mismatch = "(#{number} <= #{number_was})"
    message = "cannot be less than or equal to the previous number #{mismatch}"
    errors.add(:number, message)
  end
end
