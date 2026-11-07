namespace :research do
  desc "Evaluate fixed original synthetic retrieval/support/temporal baselines only in the test database"
  task evaluate: :environment do
    require Rails.root.join("lib/research/acceptance")
    puts JSON.pretty_generate(Research::Acceptance.new.call)
  end
  desc "Purge disallowed research text/vectors/derived bodies, preserving tombstones and billing receipts"
  task dispose: :environment do
    puts JSON.generate(Research::Disposal.sweep!)
  end

  desc "Purge an explicitly selected owner's research; never erase consumption or uncertain billing"
  task purge_owner: :environment do
    abort "Require RESEARCH_OWNER_ID and CONFIRM_PURGE_RESEARCH=YES" unless ENV["CONFIRM_PURGE_RESEARCH"] == "YES" &&
      ENV["RESEARCH_OWNER_ID"].to_s.match?(/\A[1-9][0-9]*\z/)
    Research::Disposal.purge_owner!(User.find(ENV.fetch("RESEARCH_OWNER_ID")))
  end

  desc "Interrupt restored paid work and purge disallowed research while traffic remains gated"
  task restore_review: :environment do
    puts JSON.generate(Research::RestoreGate.review!)
    puts "Keep RESEARCH_RESTORE_PENDING=1 until backup rights, outside billing/quota and restore purge are reviewed; restart with 0 only after clearance."
  end
  desc "Interrupt expired research leases and redact expired chat bodies without paid replay"
  task recover: :environment do
    Research::Agent::Lifecycle.recover!
  end

  desc "Prepare private one-way Equibles key groups for shared local quota accounting"
  task prepare_quota_keys: :environment do
    Research::SourceQuota.prepare_key_groups!
  end
end
