class SandboxMandatesController < SandboxAccountsController
  def create
    SandboxLedger.new(current_user).draft!(account_id: params[:sandbox_account_id], terms: mandate_terms)
    redirect_to sandbox_account_path(params[:sandbox_account_id]), notice: "Immutable draft created. Review and password-approve before any synthetic fill."
  end

  def transition
    SandboxLedger.new(current_user).transition!(account_id: params[:sandbox_account_id], mandate_id: params[:id],
                                               to: params[:state], password: params[:current_password])
    redirect_to sandbox_account_path(params[:sandbox_account_id]), notice: "Synthetic mandate state changed. Pause/revoke never liquidates holdings."
  end

  def execute
    allowed = %w[controller action sandbox_account_id id request_key authenticity_token commit]
    unless (params.keys - allowed).empty?
      raise SandboxLedger::Denied, "Only a request identity is accepted; orders cannot use model, provider, or caller-supplied prices."
    end
    order = SandboxLedger.new(current_user).execute!(account_id: params[:sandbox_account_id], mandate_id: params[:id],
                                                    request_key: params[:request_key])
    redirect_to sandbox_account_path(params[:sandbox_account_id]),
                notice: "SYNTHETIC fill ##{order.id} (or original idempotent result). No broker was contacted."
  end

  private

  def mandate_terms
    terms = params.require(:sandbox_mandate)
    allowed = SandboxMandate::BOUNDS.map(&:to_s) + ["expires_at"]
    raise SandboxLedger::Denied, "Unsupported mandate fields." unless (terms.keys - allowed).empty?

    terms.permit(*allowed).to_h
  end
end
