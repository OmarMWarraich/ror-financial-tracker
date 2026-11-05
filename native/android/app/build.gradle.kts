import java.net.URI

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val developmentBaseUrl = providers.gradleProperty("financialTrackerBaseUrl")
    .getOrElse("http://10.0.2.2:3000")
val parsedBaseUrl = URI(developmentBaseUrl)
require(
    Regex("""http://(10\.0\.2\.2|127\.0\.0\.1|localhost)(:[0-9]{1,5})?/?""").matches(developmentBaseUrl) &&
        parsedBaseUrl.scheme == "http" &&
        parsedBaseUrl.host in setOf("10.0.2.2", "127.0.0.1", "localhost") &&
        parsedBaseUrl.rawUserInfo == null &&
        parsedBaseUrl.rawQuery == null && parsedBaseUrl.rawFragment == null &&
        parsedBaseUrl.rawPath.orEmpty() in setOf("", "/") &&
        (parsedBaseUrl.port == -1 || parsedBaseUrl.port in 1..65535)
) { "financialTrackerBaseUrl must be an HTTP emulator/loopback origin without credentials or a path" }

android {
    namespace = "dev.financialtracker.shell"
    compileSdk = 35
    defaultConfig {
        applicationId = "dev.financialtracker.shell"
        minSdk = 28
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        buildConfigField("String", "BASE_URL", "\"$developmentBaseUrl\"")
    }
    buildFeatures { buildConfig = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin { jvmToolchain(17) }

dependencies {
    implementation("dev.hotwire:core:1.4.0")
    implementation("dev.hotwire:navigation-fragments:1.4.0")
    implementation("com.google.android.material:material:1.12.0")
    testImplementation("junit:junit:4.13.2")
}
