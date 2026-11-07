namespace :research do
  desc "Interrupt expired research leases and redact expired chat bodies without paid replay"
  task recover: :environment do
    Research::Agent::Lifecycle.recover!
  end

  desc "Prepare private one-way Equibles key groups for shared local quota accounting"
  task prepare_quota_keys: :environment do
    Research::SourceQuota.prepare_key_groups!
  end
end
