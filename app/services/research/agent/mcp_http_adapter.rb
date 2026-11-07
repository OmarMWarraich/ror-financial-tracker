require "faraday"
require "openai"

module Research
  module Agent
    class McpHttpAdapter < Faraday::Adapter
      def initialize(app, client: OpenAI::NetHTTPClient.new)
        super(app)
        @client = client
      end

      def call(env)
        super
        request = OpenAI::HTTPClient::Request.new(method: env.method, url: env.url,
          headers: env.request_headers.to_h, body: env.body, timeout: env.request.timeout)
        response = @client.execute(request)
        save_response(env, response.status, "", response.headers)
        bytes = 0
        response.body.each do |chunk|
          bytes += chunk.bytesize
          raise Research::Error.new("mcp_response_too_large") if bytes > 262_144
          if env.request.on_data
            env.request.on_data.call(chunk, bytes, env)
          else
            env.response_body << chunk
          end
        end
        @app.call(env)
      rescue OpenAI::Errors::APITimeoutError
        raise Research::Error.new("mcp_timeout"), cause: nil
      rescue OpenAI::Errors::APIConnectionError
        raise Research::Error.new("mcp_connection_failed"), cause: nil
      ensure
        OpenAI::Internal::Util.close_fused!(response.body) if response
      end
    end
  end
end
