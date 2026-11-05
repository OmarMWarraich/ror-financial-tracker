require "json"

def assert(condition, message)
  abort(message) unless condition
end

configs = {
  ios: "ios/FinancialTracker/path-configuration.json",
  android: "android/app/src/main/assets/json/path-configuration.json"
}

configs.each do |platform, path|
  config = JSON.parse(File.read(File.join(__dir__, path)))
  assert(config.fetch("settings").fetch("schema_version") == 1, "#{platform}: schema version")
  properties_for = lambda do |path|
    config.fetch("rules").each_with_object({}) do |rule, properties|
      if rule.fetch("patterns").any? { |pattern| Regexp.new(pattern).match?(path) }
        properties.merge!(rule.fetch("properties"))
      end
    end
  end

  ["/", "/sandbox_accounts", "/sandbox_accounts/1", "/research_demo", "/research_demo/1"].each do |path|
    properties = properties_for.call(path)
    assert(properties["context"] == "default", "#{platform}: #{path} context")
    assert(properties["presentation"] == "default", "#{platform}: #{path} presentation")
    assert(properties["pull_to_refresh_enabled"] == false, "#{platform}: #{path} refresh")
    if platform == :android
      assert(properties["uri"] == "hotwire://fragment/web", "#{platform}: #{path} destination")
    end
  end

  ["/users/sign_in", "/users/sign_up", "/users/password/new"].each do |path|
    properties = properties_for.call(path)
    assert(properties["context"] == "modal", "#{platform}: #{path} context")
    if platform == :android
      assert(properties["uri"] == "hotwire://fragment/web/modal/sheet", "#{platform}: #{path} destination")
    end
  end
end

puts "Bundled iOS/Android path configuration: 16 route cases passed"
