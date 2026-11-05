package dev.financialtracker.shell

import java.net.URI

class DevelopmentURLPolicy(value: String = "http://10.0.2.2:3000") {
    val baseUrl = URI(value)

    init {
        require(
            Regex("""http://(10\.0\.2\.2|127\.0\.0\.1|localhost)(:[0-9]{1,5})?/?""").matches(value) &&
                baseUrl.scheme == "http" &&
                baseUrl.host in setOf("10.0.2.2", "127.0.0.1", "localhost") &&
                baseUrl.rawUserInfo == null &&
                baseUrl.rawQuery == null && baseUrl.rawFragment == null &&
                baseUrl.rawPath.orEmpty() in setOf("", "/") &&
                (baseUrl.port == -1 || baseUrl.port in 1..65535)
        ) { "Invalid development base URL" }
    }

    val configurationUrl: String
        get() = baseUrl.resolve("/configurations/android_v1.json").toString()

    fun allows(value: String): Boolean = runCatching {
        val url = URI(value)
        url.scheme == baseUrl.scheme && url.host == baseUrl.host &&
            effectivePort(url) == effectivePort(baseUrl) && url.rawUserInfo == null
    }.getOrDefault(false)

    private fun effectivePort(url: URI) = if (url.port == -1) 80 else url.port
}
