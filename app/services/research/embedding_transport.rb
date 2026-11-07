require "openai"

module Research
  class EmbeddingTransport < OpenAI::HTTPClient
    MAX_BYTES = 1_048_576

    def initialize(client: OpenAI::NetHTTPClient.new)
      @client = client
    end

    def execute(request)
      url = request.url
      unless url.scheme == "https" && url.host == "api.openai.com" && [nil, 443].include?(url.port) &&
             url.userinfo.nil? && url.fragment.nil? && url.query.nil? &&
             url.path == "/v1/embeddings" && request.method == :post
        raise Error.new("embedding_endpoint_rejected")
      end
      response = @client.execute(request)
      received_bytes = 0
      body = response.body.lazy.map do |chunk|
        received_bytes += chunk.bytesize
        raise Error.new("embedding_response_too_large") if received_bytes > MAX_BYTES
        chunk
      end
      OpenAI::HTTPClient::Response.new(status: response.status, headers: response.headers, body: body)
    end
  end
end
