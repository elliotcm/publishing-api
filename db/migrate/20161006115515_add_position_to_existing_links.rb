class AddPositionToExistingLinks < ActiveRecord::Migration
  def change
    Link.where(position: nil).update_all(position: 0)
  end
end
