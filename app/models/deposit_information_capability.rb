class DepositInformationCapability
  BLOCKERS = [
    "No account, crypto asset, product or network has been verified for this capability.",
    "Legacy deposit addresses do not explicitly identify their asset/network or whether a memo/tag is required.",
    "Minimums and fees are optional in the legacy methods schema; missing values must block address display.",
    "The newer Funding Beta API needs a separate reviewed contract; its identifiers and schemas cannot be mixed with legacy responses.",
    "Dedicated encrypted credentials, fresh scope inspection and bounded transport are not implemented. Do not submit a key."
  ].freeze

  def available?
    false
  end

  def blockers
    BLOCKERS
  end
end
