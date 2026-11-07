module Research
  module Chat
    def self.enabled?
      ENV["RESEARCH_CHAT_ENABLED"] == "1"
    end

    def self.stream(conversation)
      "research-chat:#{conversation.user_id}:#{conversation.id}"
    end

    class Updates
      INTERVAL = 0.3

      def initialize(run)
        @run = run
        @last_sent = 0
      end

      def call(event)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return if now - @last_sent < INTERVAL && !event.fetch("type").start_with?("run.")
        refresh!
        @last_sent = now
      end

      def refresh!
        return unless Chat.enabled? && @run.conversation_id
        ActionCable.server.broadcast(Chat.stream(@run.conversation), { "version" => 1, "refresh" => true })
      rescue Redis::BaseError, RedisClient::Error => error
        Rails.logger.warn("Research run #{@run.id} stream delivery unavailable type=#{error.class.name}; canonical state remains authoritative")
      end
    end
  end
end
