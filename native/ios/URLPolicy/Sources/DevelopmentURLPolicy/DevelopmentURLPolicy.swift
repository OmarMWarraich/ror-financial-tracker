import Foundation

public struct DevelopmentURLPolicy {
    public enum ConfigurationError: Error { case invalidBaseURL }
    public let baseURL: URL

    public init(_ value: String = "http://127.0.0.1:3000") throws {
        guard value.range(of: #"^http://(127\.0\.0\.1|localhost)(:[0-9]{1,5})?/?$"#, options: .regularExpression) != nil,
              let components = URLComponents(string: value),
              components.scheme == "http",
              ["127.0.0.1", "localhost"].contains(components.host ?? ""),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              (1...65535).contains(components.port ?? 80),
              let url = components.url else {
            throw ConfigurationError.invalidBaseURL
        }
        baseURL = url
    }

    public var configurationURL: URL {
        baseURL.appendingPathComponent("configurations/ios_v1.json")
    }

    public func allows(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme == baseURL.scheme &&
            components.host == baseURL.host &&
            (components.port ?? 80) == (baseURL.port ?? 80) &&
            components.user == nil && components.password == nil
    }
}
