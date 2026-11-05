# Real-Rails isolated iOS follow-up

This is distinct from the synthetic fixture-server test in [README.md](README.md) and from the simulator build.

## Result, 2026-11-05

**1 XCUITest passed, 0 failures, 9.834 seconds (`TEST SUCCEEDED`)**, using the real Rails application at `http://127.0.0.1:3000`.

The test-owned iPhone 17 Pro / iOS 26.5 simulator was newly created as `FinancialTracker Real Rails Smoke 5204a739`, UDID `31921EEF-DE64-468A-A04F-8C66110C469E`. No shared simulator was used. This simulator was shut down and deleted after the test.

Verified in the actual native app:

1. Anonymous launch at the protected Rails `/` route reaches the Rails sign-in form.
2. Tapping the existing **Research policy lab** link opens the real public `/research_demo` page and its **Synthetic research policy lab** heading.
3. Tapping the existing **FinanceTracker** link back to protected `/` returns to the Rails sign-in form.

No client implementation was changed to reach these pages: the follow-up only adds a separate native UI-test target/scheme. An initial run failed because the test selector used the HTML document title instead of the visible heading; correcting that test-only selector produced the passing result above.

## Authentication remains unverified

Before creating an account or entering any password, the test typed the explicitly nonsecret, never-submitted string `NONSECRET_REDACTION_PROBE` into the secure field. XCTest printed:

```text
Type 'NONSECRET_REDACTIO...' into "Password" SecureTextField
```

Thus `XCUIElement.typeText` is not safely redacting secret input in this installed test environment. Actual signup/sign-in was not attempted because it would risk logging/storing password input, contrary to this acceptance run's constraint. No password was generated, no form was submitted, no account was registered, and no existing account or private record was accessed. **There is no synthetic user to remove.**

This is a test-harness secret-handling blocker, not evidence that the Rails login implementation failed. Signup, cookie-authenticated native navigation, sign-out, expiry, authorization, step-up and revocation remain unverified. No native-only login API, WebView injection, test bridge, authentication bypass, or other real-client change was introduced to work around that constraint.

No sandbox account/ledger was created. No private screenshots, real-device access, signing/distribution or store operation was performed. No new native test server was needed; the Rails stack was left running and unchanged. The test-owned simulator was deleted; no native smoke helper process remains.

## Command

Create a new isolated simulator as shown in [README.md](README.md), then run the separately opted-in Rails scheme:

```sh
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all \
  xcodebuild -project native/ios/FinancialTracker.xcodeproj \
  -scheme FinancialTrackerRailsSmoke -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath native/ios/build \
  -parallel-testing-enabled NO \
  -only-testing:FinancialTrackerRailsSmokeTests/RealRailsSessionTests \
  CODE_SIGNING_ALLOWED=NO test
```

The actual run also used `-resultBundlePath native/smoke/rails-results.xcresult` and an ignored `native/smoke/rails-test.log`. Clean up only the simulator you created. Do not extend the test with real password entry until test-activity secret handling has been reviewed.

After the separate disposable-auth experiment failed, that attempted flow was removed from executable source. The complete default `FinancialTrackerRailsSmoke` scheme was rerun **without `-only-testing` or `-skip-testing`**: **1 anonymous navigation test passed, 0 failures, 10.231s, TEST SUCCEEDED**. It does not execute signup or depend on port 3101. The test-owned simulator was deleted afterward.
