class Users::RegistrationsController < Devise::RegistrationsController
  def destroy
    resource.with_lock do
      if SandboxAccount.exists?(user_id: resource.id)
        redirect_to edit_user_registration_path,
                    alert: "Account deletion is unavailable while an append-only synthetic sandbox ledger exists. A reviewed retention and account-closure workflow is required."
      else
        super
      end
    end
  end
end
