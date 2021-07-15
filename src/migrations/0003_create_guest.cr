class CreateGuestMigration
  include Clear::Migration

  def change(direction)
    direction.up do
      create_table(:guests) do |t|
        t.references to: "tenants", name: "tenant_id", on_delete: "cascade", null: false

        t.column :name, :string
        t.column :email, :string
        t.column :preferred_name, :string
        t.column :phone, :string
        t.column :organisation, :string
        t.column :notes, :text
        t.column :photo, :string
        t.column :banned, :boolean, default: "false"
        t.column :dangerous, :boolean, default: "false"
        t.column :searchable, :string
        t.column :extension_data, :jsonb

        t.timestamps
      end

      execute("CREATE UNIQUE INDEX idx_lower_unique_guests_email ON guests (lower(email), tenant_id)")
    end

    direction.down do
      execute("DROP TABLE guests")
    end
  end
end
