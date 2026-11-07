module Research
  module Agent
    MODEL = "gpt-5.4-mini-2026-03-17"
    PROMPT_VERSION = "research-tools-v1"
    INPUT_PRICE = 750
    OUTPUT_PRICE = 4500
    Usage = Struct.new(:input_tokens, :output_tokens, keyword_init: true)
    ToolCall = Struct.new(:id, :name, :arguments, keyword_init: true)
    ModelResult = Struct.new(:text, :tool_calls, :output, :usage, :deltas, keyword_init: true)
    Result = Struct.new(:run_id, :status, :text, :sources, :usage, keyword_init: true)

    class ProviderError < Research::Error
      attr_reader :usage

      def initialize(code, usage: nil)
        @usage = usage
        super(code)
      end
    end

    class Cancellation
      def initialize
        @mutex = Mutex.new
        @cancelled = false
      end

      def cancel!
        @mutex.synchronize { @cancelled = true }
      end

      def check!
        raise Research::Error.new("agent_cancelled") if @mutex.synchronize { @cancelled }
      end
    end

    def self.safe_text!(text, forbidden: [], bytes: 65_536)
      unless text.is_a?(String) && text.valid_encoding? && text.bytesize <= bytes &&
             !text.match?(/[\x00-\x08\x0B\x0C\x0E-\x1F]/) &&
             !text.match?(Chunker::SECRET) && forbidden.none? { |key| key.present? && text.include?(key) }
        raise Research::Error.new("agent_content_rejected")
      end
      text
    end
  end
end
