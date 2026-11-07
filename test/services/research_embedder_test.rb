require "test_helper"
require "openai"

class ResearchEmbedderTest < ActiveSupport::TestCase
  setup do
    @space = ResearchEmbeddingSpace.new(provider: "openai")
    @passages = ["Original one", "Original two"].map do |text|
      ResearchPassage.new(content: text, token_count: Research::Chunker.new.tokens(text))
    end
    @http = FakeHTTP.new
    @http.body = response
    client = OpenAI::Client.new(api_key: "original-offline-dummy", base_url: "https://api.openai.com/v1",
      max_retries: 0, timeout: 5, log_level: :off, http_client: Research::EmbeddingTransport.new(client: @http))
    @embedder = Research::Embedder.new(@space, client: client)
    @embedder.prepare!
  end

  test "official SDK serializes bounded embeddings and validates ordering and usage offline" do
    result = @embedder.call(@passages, timeout: 3, idempotency_key: "original-attempt")
    assert_equal 1536, result.vectors.first.size
    assert_equal 1.0, result.vectors.first[0]
    assert_equal 1.0, result.vectors.last[1]
    assert_equal @passages.sum(&:token_count), result.tokens
    request = @http.requests.first
    body = JSON.parse(request.body)
    assert_equal @passages.map(&:content), body["input"]
    assert_equal "text-embedding-3-small", body["model"]
    assert_equal 1536, body["dimensions"]
    assert_equal "float", body["encoding_format"]
    assert_equal 3, request.timeout
    assert_equal "original-attempt", request.headers.find { |name, _value| name.casecmp?("idempotency-key") }.last
    assert_equal 1, @http.requests.size
  end

  test "invalid vector counts indexes dimensions norms and float32 values are rejected" do
    [[->(body) { body["data"].pop }, "invalid_embedding_response"],
     [->(body) { body["data"][0]["index"] = 9 }, "invalid_embedding_response"],
     [->(body) { body["data"][0]["embedding"] = [1.0] }, "invalid_embedding_vector"],
     [->(body) { body["data"][0]["embedding"] = [0.0] * 1536 }, "invalid_embedding_vector"],
     [->(body) { body["data"][0]["embedding"] = [1e-100] * 1536 }, "invalid_embedding_vector"],
     [->(body) { body["data"][0]["embedding"] = [1e100] * 1536 }, "invalid_embedding_vector"],
     [->(body) { body["usage"]["total_tokens"] = 100 }, "embedding_usage_exceeded_reservation"]].each do |change, expected|
      body = JSON.parse(response)
      change.call(body)
      @http.body = JSON.generate(body)
      assert_equal expected, assert_raises(Research::Error) {
        @embedder.call(@passages, timeout: 1, idempotency_key: "original")
      }.code
    end
  end

  test "timeout rate-limit and oversized replies have explicit errors and no retry" do
    @http.status = 429
    @http.body = '{"error":{"message":"Original offline rate-limit","type":"rate_limit"}}'
    assert_equal "embedding_provider_error", assert_raises(Research::Error) {
      @embedder.call(@passages, timeout: 1, idempotency_key: "original")
    }.code
    assert_equal 1, @http.requests.size
    @http.status = 200
    @http.timeout = true
    assert_equal "embedding_timeout", assert_raises(Research::Error) {
      @embedder.call(@passages, timeout: 1, idempotency_key: "original")
    }.code
    assert_equal 2, @http.requests.size
    @http.timeout = false
    @http.body = "x" * (Research::EmbeddingTransport::MAX_BYTES + 1)
    assert_equal "embedding_response_too_large", assert_raises(Research::Error) {
      @embedder.call(@passages, timeout: 1, idempotency_key: "original")
    }.code
  end

  test "server credential rotation does not reuse a client approved with another key" do
    original = ENV["OPENAI_API_KEY"]
    ENV["OPENAI_API_KEY"] = "original-offline-key-one"
    embedder = Research::Embedder.new(@space)
    embedder.prepare!
    ENV["OPENAI_API_KEY"] = "original-offline-key-two"
    assert_equal "openai_credentials_changed", assert_raises(Research::Error) { embedder.prepare! }.code
  ensure
    ENV["OPENAI_API_KEY"] = original
  end

  private

  def response
    JSON.generate(model: "text-embedding-3-small", object: "list",
      usage: { prompt_tokens: @passages.sum(&:token_count), total_tokens: @passages.sum(&:token_count) },
      data: [1, 0].map do |index|
        { object: "embedding", index: index, embedding: Array.new(1536, 0.0).tap { |vector| vector[index] = 1.0 } }
      end)
  end

  class FakeHTTP
    attr_accessor :body, :status, :timeout
    attr_reader :requests
    def initialize
      @requests = []
      @status = 200
    end
    def execute(request)
      @requests << request
      raise OpenAI::Errors::APITimeoutError.new(url: request.url) if timeout
      OpenAI::HTTPClient::Response.new(status: status, headers: { "content-type" => "application/json" }, body: body)
    end
  end
end
