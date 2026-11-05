import DevelopmentURLPolicy
@preconcurrency import HotwireNative
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    private(set) var policy: DevelopmentURLPolicy?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        do {
            let policy = try DevelopmentURLPolicy(
                ProcessInfo.processInfo.environment["FINANCIAL_TRACKER_BASE_URL"] ?? "http://127.0.0.1:3000"
            )
            self.policy = policy
            Hotwire.config.applicationUserAgentPrefix = "FinancialTracker;"
            Hotwire.config.debugLoggingEnabled = false
            Hotwire.config.pathConfiguration.matchQueryStrings = false
            Hotwire.registerRouteDecisionHandlers([SameOriginRouteDecisionHandler(policy: policy)])
            Hotwire.loadPathConfiguration(from: [
                .file(Bundle.main.url(forResource: "path-configuration", withExtension: "json")!),
                .server(policy.configurationURL)
            ])
        } catch {
            // SceneDelegate shows a local error instead of loading an untrusted fallback.
            policy = nil
        }
        return true
    }
}

struct SameOriginRouteDecisionHandler: RouteDecisionHandler {
    let name = "development-same-origin-only"
    let policy: DevelopmentURLPolicy

    func matches(proposal: VisitProposal, configuration: Navigator.Configuration) -> Bool { true }

    func handle(proposal: VisitProposal,
                configuration: Navigator.Configuration,
                navigator: Navigating) -> Router.Decision {
        policy.allows(proposal.url) ? .navigate : .cancel
    }
}
