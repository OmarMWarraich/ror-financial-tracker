encryption_keys = {
  primary_key: ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"],
  deterministic_key: ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"],
  key_derivation_salt: ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]
}

if encryption_keys.values.all?(&:present?)
  encryption_keys.each do |name, value|
    Rails.application.config.active_record.encryption.public_send("#{name}=", value)
  end
end
