require "net/http"
require "timeout"

module Research
  class EquiblesTransport
    def initialize(on_headers: nil)
      @on_headers = on_headers
    end

    def call(uri:, api_key:, timeout:)
      observed_status = observed_headers = nil
      unless uri.scheme == "https" && uri.host == "api.equibles.com" && uri.port == 443
        raise Error.new("source_endpoint_rejected")
      end
      result = nil
      Timeout.timeout(timeout, Error, "source_timeout") do
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = timeout
        http.read_timeout = timeout
        http.write_timeout = timeout
        http.max_retries = 0
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{api_key}"
        request["Accept"] = "application/json"
        request["Accept-Encoding"] = "identity"
        http.request(request) do |response|
          observed_status = response.code.to_i
          observed_headers = %w[x-ratelimit-remaining ratelimit-remaining retry-after].to_h { |name| [name, response[name]] }.compact
          case response.code.to_i
          when 200
            unless response["content-type"].to_s.match?(/\Aapplication\/json(?:;|\z)/i)
              raise Error.new("invalid_source_response")
            end
            body = +""
            response.read_body do |chunk|
              body << chunk
              raise Error.new("source_too_large") if body.bytesize > Chunker::MAX_BYTES
            end
            result = JSON.parse(body)
            raise Error.new("invalid_source_response") unless result.is_a?(Hash)
          when 401, 403 then raise Error.new("source_access_denied")
          when 404 then raise Error.new("source_not_found")
          when 429 then raise Error.new("source_rate_limited")
          else raise Error.new("source_http_error")
          end
        end
      end
      result
    rescue JSON::ParserError
      raise Error.new("invalid_source_response")
    rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
      raise Error.new("source_timeout")
    rescue SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError
      raise Error.new("source_connection_error")
    ensure
      @on_headers&.call(observed_status, observed_headers) if observed_headers
    end
  end
end
