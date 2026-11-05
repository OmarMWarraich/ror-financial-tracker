package dev.financialtracker.shell

import org.junit.Assert.*
import org.junit.Test

class DevelopmentURLPolicyTest {
    @Test fun defaultsAndScreens() {
        val policy = DevelopmentURLPolicy()
        assertEquals("http://10.0.2.2:3000/configurations/android_v1.json", policy.configurationUrl)
        listOf("/", "/users/sign_in", "/sandbox_accounts", "/research_demo").forEach {
            assertTrue(policy.allows("http://10.0.2.2:3000$it"))
        }
    }

    @Test fun explicitLoopback() {
        val policy = DevelopmentURLPolicy("http://127.0.0.1:3001/")
        assertTrue(policy.allows("http://127.0.0.1:3001/sandbox_accounts"))
        assertFalse(policy.allows("http://127.0.0.1:3000/"))
    }

    @Test fun invalidConfiguration() {
        listOf(
            "", "not a url", "https://10.0.2.2:3000", "file:///etc/passwd",
            "http://example.com", "http://10.0.2.2.evil.test", "http://user@localhost",
            "http://localhost:", "http://localhost:0", "http://localhost:65536", "http://localhost/path",
            "http://localhost?x=1", "http://localhost#fragment"
        ).forEach {
            assertThrows(Exception::class.java) { DevelopmentURLPolicy(it) }
        }
    }

    @Test fun externalNavigationIsRejected() {
        val policy = DevelopmentURLPolicy()
        listOf(
            "http://example.com/", "https://10.0.2.2:3000/", "http://10.0.2.2:3001/",
            "http://user@10.0.2.2:3000/", "file:///etc/passwd", "not a url"
        ).forEach { assertFalse(policy.allows(it)) }
    }
}
