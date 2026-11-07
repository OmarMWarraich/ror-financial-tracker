require "faraday"

module Research
  module Agent
    class McpEndpointGuard < Faraday::Middleware
      ENDPOINT = "https://mcp.equibles.com/mcp"
      METHODS = %w[initialize notifications/initialized tools/list tools/call notifications/cancelled].freeze

      def initialize(app, before_request:)
        super(app)
        @before_request = before_request
      end

      def call(env)
        unless env.url.to_s == ENDPOINT && %i[post delete].include?(env.method)
          raise Research::Error.new("mcp_endpoint_rejected")
        end
        if env.method == :post
          body = JSON.parse(env.body)
          unless body.is_a?(Hash) && METHODS.include?(body["method"])
            raise Research::Error.new("mcp_method_rejected")
          end
        end
        method = env.method == :delete ? "session/close" : body["method"]
        remaining = @before_request.call(method)
        env.request.timeout = [remaining, 5.0].min
        env.request.open_timeout = [remaining, 5.0].min
        @app.call(env)
      rescue Faraday::TimeoutError
        raise Research::Error.new("mcp_timeout"), cause: nil
      rescue JSON::ParserError
        raise Research::Error.new("mcp_request_rejected"), cause: nil
      end
    end
  end
end
