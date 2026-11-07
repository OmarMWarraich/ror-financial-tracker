require "openai"

module Research
  class Embedder
    Result = Struct.new(:vectors, :tokens, keyword_init: true)

    def initialize(space, client: nil)
      @space = space
      @client = client
      @injected_client = !client.nil?
    end

    def prepare!
      return if @space.provider == "synthetic" || @injected_client
      key = ENV["OPENAI_API_KEY"].to_s.strip
      raise Error.new("openai_credentials_required") if key.blank?
      raise Error.new("openai_credentials_invalid") unless key.valid_encoding? && key.length <= 4096 && !key.match?(/\s/)
      fingerprint = Digest::SHA256.hexdigest(key)
      if @client
        raise Error.new("openai_credentials_changed") unless @credential_fingerprint == fingerprint
        return
      end
      @credential_fingerprint = fingerprint
      @client = OpenAI::Client.new(api_key: key, base_url: "https://api.openai.com/v1",
                                   max_retries: 0, timeout: 5, log_level: :off, http_client: EmbeddingTransport.new)
    end

    def call(passages, timeout:, idempotency_key:)
      unless passages.size.between?(1, 4) && passages.all? { |part| part.token_count.between?(1, 800) }
        raise Error.new("embedding_input_limit")
      end
      if @space.provider == "synthetic"
        vectors = passages.map do |part|
          bytes = Digest::SHA256.digest(part.content).bytes
          Array.new(1536) { |index| (bytes[index % bytes.size] - 127.5) / 128.0 }
        end
        return Result.new(vectors: vectors, tokens: passages.sum(&:token_count))
      end
      response = @client.embeddings.create(
        model: "text-embedding-3-small", input: passages.map(&:content), dimensions: 1536, encoding_format: :float,
        request_options: { timeout: [timeout, 5.0].min, max_retries: 0, idempotency_key: idempotency_key,
                           extra_headers: { "Idempotency-Key" => idempotency_key }, include_raw_body: false }
      )
      usage = response.usage&.total_tokens
      usage = nil unless usage.is_a?(Integer) && usage.between?(1, 300_000)
      data = response.data
      unless usage && response.model == "text-embedding-3-small" && data.is_a?(Array) &&
             data.size == passages.size && data.all? { |item| item.index.is_a?(Integer) } &&
             data.map(&:index).sort == (0...passages.size).to_a
        raise Error.new("invalid_embedding_response", actual_tokens: usage)
      end
      vectors = data.sort_by(&:index).map(&:embedding)
      unless vectors.all? { |values| self.class.valid_vector?(values) }
        raise Error.new("invalid_embedding_vector", actual_tokens: usage)
      end
      if usage > passages.sum(&:token_count)
        raise Error.new("embedding_usage_exceeded_reservation", actual_tokens: usage)
      end
      Result.new(vectors: vectors, tokens: usage)
    rescue OpenAI::Errors::APITimeoutError
      raise Error.new("embedding_timeout")
    rescue OpenAI::Errors::APIError
      raise Error.new("embedding_provider_error")
    rescue OpenAI::Errors::ConversionError
      raise Error.new("invalid_embedding_response")
    rescue JSON::ParserError
      raise Error.new("invalid_embedding_response")
    end

    def self.valid_vector?(values)
      values.is_a?(Array) && values.length == 1536 &&
        values.all? { |value| value.is_a?(Numeric) && value.real? && value.to_f.finite? && value.to_f.abs <= 3.4028234e38 } &&
        values.any? { |value| [value.to_f].pack("f").unpack1("f") != 0.0 }
    end
  end
end
