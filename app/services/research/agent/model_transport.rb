require "openai"

module Research
  module Agent
    class ModelTransport < OpenAI::HTTPClient
      def initialize(client: OpenAI::NetHTTPClient.new)
        @client = client
      end

      def execute(request)
        url = request.url
        unless url.scheme == "https" && url.host == "api.openai.com" && [nil, 443].include?(url.port) &&
               url.userinfo.nil? && url.fragment.nil? && url.query.nil? &&
               url.path == "/v1/responses" && request.method == :post
          raise Research::Error.new("model_endpoint_rejected")
        end
        response = @client.execute(request)
        bytes = 0
        body = response.body.lazy.map do |chunk|
          bytes += chunk.bytesize
          raise Research::Error.new("model_response_too_large") if bytes > 1_048_576
          chunk
        end
        OpenAI::HTTPClient::Response.new(status: response.status, headers: response.headers, body: body)
      end

      def close
        @client.close
      end
    end
  end
end
