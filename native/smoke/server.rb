require "socket"
require "json"

root = File.expand_path("..", __dir__)
turbo = File.join(__dir__, "node_modules/@hotwired/turbo/dist/turbo.es2017-umd.js")
abort("Run npm ci --prefix native/smoke first") unless File.file?(turbo)

server = TCPServer.new("127.0.0.1", 3301)
trap("TERM") { server.close }
trap("INT") { server.close }
$stdout.sync = true
puts "Public synthetic native fixtures listening on http://127.0.0.1:3301"

def page(title, body)
  <<~HTML
    <!doctype html>
    <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>#{title}</title><script src="/turbo.js" defer></script></head>
    <body><h1>#{title}</h1>#{body}</body></html>
  HTML
end

begin
  loop do
    client = server.accept
    begin
      request = client.gets
      next unless request
      method, path = request.split(" ", 3)
      while (line = client.gets) && line != "\r\n"; end
      puts "#{method} #{path}"

      status = "200 OK"
      type = "text/html; charset=utf-8"
      headers = ""
      body = case path
      when "/"
        status = "302 Found"
        headers = "Location: /research_demo\r\n"
        ""
      when "/research_demo"
        page("Research fixture", <<~HTML)
          <p>Public synthetic fixture. No account data or financial operations.</p>
          <p><a href="/sandbox_accounts">Open sandbox fixture</a></p>
          <p><a href="http://example.invalid/" target="_blank">Blocked external fixture</a></p>
        HTML
      when "/sandbox_accounts"
        page("Sandbox fixture", "<p>Public synthetic sandbox fixture. No accounts exist.</p>")
      when "/configurations/ios_v1.json"
        type = "application/json"
        File.read(File.join(root, "ios/FinancialTracker/path-configuration.json"))
      when "/turbo.js"
        type = "application/javascript"
        File.read(turbo)
      else
        status = "404 Not Found"
        "Public fixture not found"
      end
      client.write("HTTP/1.1 #{status}\r\nContent-Type: #{type}\r\n#{headers}Cache-Control: no-store\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
    rescue Errno::EPIPE, Errno::ECONNRESET
      # WebKit can cancel an in-flight response while moving between native screens.
    ensure
      client.close
    end
  end
rescue IOError, Errno::EBADF
  raise unless server.closed?
end
