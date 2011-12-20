class CreateHooks < ActiveRecord::Migration
  def self.up
    create_table :hooks do |t|
      t.integer :repository_id
      t.string :name
      t.text :options

      t.timestamps
    end
  end

  def self.down
    drop_table :hooks
  end
end
