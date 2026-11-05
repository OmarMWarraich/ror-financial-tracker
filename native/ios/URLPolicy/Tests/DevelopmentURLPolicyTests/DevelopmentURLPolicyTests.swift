import Foundation
import Testing
@testable import DevelopmentURLPolicy

@Test func defaultsAndSameOriginScreens() throws {
    let policy = try DevelopmentURLPolicy()
    #expect(policy.configurationURL.absoluteString == "http://127.0.0.1:3000/configurations/ios_v1.json")
    for path in ["/", "/users/sign_in", "/sandbox_accounts", "/research_demo"] {
        #expect(policy.allows(URL(string: "http://127.0.0.1:3000\(path)")!))
    }
}

@Test func explicitLocalBaseURL() throws {
    let policy = try DevelopmentURLPolicy("http://localhost:3001/")
    #expect(policy.allows(URL(string: "http://localhost:3001/sandbox_accounts")!))
    #expect(!policy.allows(URL(string: "http://localhost:3000/")!))
    #expect(!policy.allows(URL(string: "http://127.0.0.1:3001/")!))
}

@Test func invalidConfigurationFailsClosed() {
    for value in [
        "", "not a url", "https://127.0.0.1:3000", "file:///etc/passwd",
        "javascript:alert(1)", "http://example.com", "http://10.0.2.2:3000",
        "http://127.0.0.1.evil.test", "http://user:pass@localhost:3000",
        "http://localhost:", "http://localhost:0", "http://localhost:65536", "http://localhost/path",
        "http://localhost?x=1", "http://localhost#fragment"
    ] {
        #expect(throws: DevelopmentURLPolicy.ConfigurationError.self) {
            try DevelopmentURLPolicy(value)
        }
    }
}

@Test func externalNavigationIsRejected() throws {
    let policy = try DevelopmentURLPolicy()
    for value in [
        "http://example.com/", "https://127.0.0.1:3000/", "http://127.0.0.1:3001/",
        "http://user@127.0.0.1:3000/", "mailto:hello@example.com", "file:///etc/passwd"
    ] {
        #expect(!policy.allows(URL(string: value)!))
    }
}
