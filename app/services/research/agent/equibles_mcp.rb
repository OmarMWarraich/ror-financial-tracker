require "mcp"
require "mcp/client"
require "event_stream_parser"

module Research
  module Agent
    class EquiblesMcp
      def initialize(user:, registry:, before_request:, client: nil)
        @user, @registry, @before_request = user, registry, before_request
        @client = client
        @injected = !client.nil?
        @cancellation = MCP::Cancellation.new
      end

      def discover!
        prepare!
        @client.connect(protocol_version: "2025-11-25", capabilities: {}, mode: :legacy)
        cursor = nil
        seen = []
        2.times do
          page = @client.list_tools(cursor: cursor, cancellation: @cancellation)
          unless page.tools.is_a?(Array) && page.tools.size <= 200
            raise Research::Error.new("mcp_discovery_too_large")
          end
          @registry.register!(page.tools)
          cursor = page.next_cursor
          return @registry.definitions if cursor.nil?
          unless cursor.is_a?(String) && cursor.valid_encoding? && cursor.bytesize <= 1024 && !seen.include?(cursor)
            raise Research::Error.new("invalid_mcp_cursor")
          end
          seen << cursor
        end
        raise Research::Error.new("mcp_discovery_page_limit")
      rescue MCP::Client::RequestHandlerError, MCP::Client::ServerError, MCP::Client::ValidationError
        raise Research::Error.new("mcp_discovery_failed"), cause: nil
      end

      def call(name, arguments, forbidden: [])
        @registry.validate!(name, arguments)
        prepare!
        raw = @client.call_tool(name: name, arguments: arguments, cancellation: @cancellation)
        result = raw.is_a?(Hash) ? raw["result"] : nil
        unless result.is_a?(Hash) && [nil, false].include?(result["isError"]) && result["content"].is_a?(Array) &&
               result["content"].size.between?(1, 10) && !result.key?("inputRequests") && !result.key?("requestState")
          raise Research::Error.new("mcp_tool_failed")
        end
        Agent.safe_text!(JSON.generate(result), forbidden: forbidden, bytes: 262_144)
        text = result["content"].map do |part|
          raise Research::Error.new("mcp_content_not_allowlisted") unless part.is_a?(Hash) && part["type"] == "text"
          Agent.safe_text!(part["text"], forbidden: forbidden, bytes: 262_144)
        end.join("\n")
        Agent.safe_text!(text, forbidden: forbidden, bytes: 262_144)
        { "text" => text, "structured" => result["structuredContent"], "protocol_version" => @client.protocol_version }
      rescue MCP::CancelledError
        raise Research::Error.new("agent_cancelled"), cause: nil
      rescue MCP::Client::RequestHandlerError, MCP::Client::ServerError, MCP::Client::ValidationError, MCP::Client::InputRequiredError
        raise Research::Error.new("mcp_tool_failed"), cause: nil
      end

      def cancel!
        @cancellation.cancel(reason: "application cancellation")
      end

      def close
        @client&.transport&.close
      rescue MCP::Client::RequestHandlerError, MCP::Client::ServerError
        raise Research::Error.new("mcp_session_close_failed"), cause: nil
      ensure
        @http_client&.close
      end

      private

      def prepare!
        return if @injected
        unless EquiblesConnection.encryption_configured? && @user.equibles_connection
          raise Research::Error.new("equibles_credentials_required")
        end
        connection = @user.equibles_connection.reload
        key = connection.api_key.to_s.strip
        unless key.present? && key.valid_encoding? && key.length <= 4096 && !key.match?(/\s/)
          raise Research::Error.new("equibles_credentials_required")
        end
        fingerprint = Digest::SHA256.hexdigest(connection.read_attribute_before_type_cast(:api_key).to_s)
        if @client
          raise Research::Error.new("source_credentials_changed") unless fingerprint == @fingerprint
          return
        end
        @fingerprint = fingerprint
        @http_client = OpenAI::NetHTTPClient.new
        transport = MCP::Client::HTTP.new(url: McpEndpointGuard::ENDPOINT, headers: { "Authorization" => "Bearer #{key}" },
          max_message_bytes: 262_144, max_reconnection_wait: 0.001) do |http|
          http.use McpEndpointGuard, before_request: @before_request
          http.options.timeout = 5
          http.options.open_timeout = 5
          http.ssl.verify = true
          http.adapter McpHttpAdapter, client: @http_client
        end
        @client = MCP::Client.new(transport: transport, max_pages: 2, input_required_max_rounds: 1)
      rescue ActiveRecord::Encryption::Errors::Decryption, ActiveRecord::Encryption::Errors::Configuration
        raise Research::Error.new("equibles_credentials_unavailable"), cause: nil
      end
    end
  end
end
