class AddResearchVerificationClock < ActiveRecord::Migration[7.1]
  def up
    add_column :research_revisions, :verified_at, :datetime
    add_check_constraint :research_revisions,
                         "verified_at IS NULL OR verified_at >= received_at",
                         name: "research_verification_after_receipt"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Preserve source verification independently of receipt and retention"
  end
end
