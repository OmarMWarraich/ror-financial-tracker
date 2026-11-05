class SandboxOrder < ApplicationRecord
  belongs_to :sandbox_account
  belongs_to :sandbox_mandate
  belongs_to :user

  def readonly?
    persisted?
  end
end
