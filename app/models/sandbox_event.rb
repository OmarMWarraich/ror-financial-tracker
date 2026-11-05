class SandboxEvent < ApplicationRecord
  belongs_to :sandbox_account

  def readonly?
    persisted?
  end
end
