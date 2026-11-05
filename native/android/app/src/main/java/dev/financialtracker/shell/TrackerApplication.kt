package dev.financialtracker.shell

import android.app.Application
import dev.hotwire.core.config.Hotwire
import dev.hotwire.core.turbo.config.PathConfiguration
import dev.hotwire.core.turbo.visit.VisitProposal
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.config.registerRouteDecisionHandlers
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import dev.hotwire.navigation.routing.Router

class TrackerApplication : Application() {
    val policy = DevelopmentURLPolicy(BuildConfig.BASE_URL)

    override fun onCreate() {
        super.onCreate()
        Hotwire.config.applicationUserAgentPrefix = "FinancialTracker;"
        Hotwire.config.webViewDebuggingEnabled = false
        Hotwire.registerRouteDecisionHandlers(SameOriginRouteDecisionHandler(policy))
        Hotwire.loadPathConfiguration(
            context = this,
            location = PathConfiguration.Location(
                assetFilePath = "json/path-configuration.json",
                remoteFileUrl = policy.configurationUrl
            )
        )
    }
}

class SameOriginRouteDecisionHandler(
    private val policy: DevelopmentURLPolicy
) : Router.RouteDecisionHandler {
    override val name = "development-same-origin-only"

    override fun matches(proposal: VisitProposal, configuration: NavigatorConfiguration) = true

    override fun handle(
        proposal: VisitProposal,
        configuration: NavigatorConfiguration,
        activity: HotwireActivity
    ) = if (policy.allows(proposal.location)) Router.Decision.NAVIGATE else Router.Decision.CANCEL
}
