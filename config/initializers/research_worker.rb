Sidekiq.configure_server do |config|
  config.on(:startup) do
    if ENV["WORKER_QUEUE"] == "research"
      Research::Agent::Lifecycle.recover!
      Rails.logger.info("Research worker recovery complete; paid interrupted runs are not replayed")
    end
  end
end
