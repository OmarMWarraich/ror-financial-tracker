# Isolated iOS simulator acceptance

This evidence is **separate from `xcodebuild build`** and does not establish Rails authentication, real-device, Android, or release acceptance.

## Actual run: 2026-11-05

- Xcode 26.5 (17F42), Swift 6.3.2, iOS 26.5 runtime.
- A new simulator was created exclusively for this run: `FinancialTracker Native Public Smoke 5204a739`, iPhone 17 Pro, UDID `614A0E8A-9C3B-474F-969A-D8886E8D9C49`.
- It was not a shared/pre-existing booted simulator. Only this test-owned simulator was used for the acceptance test and then shut down/deleted.
- `FinancialTrackerSmokeTests.PublicFixtureNavigationTests.testNativeNavigationAndBackWithPublicFixtures`: **1 test passed, 0 failures, 10.212 seconds; `TEST SUCCEEDED`.**
- Local fixture server bound only to `127.0.0.1:3301`; all text/data were synthetic and public. No account was created, authenticated, loaded, or photographed. No manual screenshots, tunnels, real-device access, store operations, or distribution signing were used.
- Test-only JavaScript dependency: official `@hotwired/turbo` **8.0.23**, pinned with npm integrity in `package-lock.json`. It is not an application runtime dependency or an external runtime CDN request.

The test asserted:

1. Launch follows the fixture's `/` redirect to `/research_demo`; the web content and native `Research fixture` navigation bar appear.
2. An external link is rejected and the fixture remains in the app.
3. `/sandbox_accounts` pushes a native screen with the native `Sandbox fixture` navigation bar and expected synthetic content.
4. The **native navigation-bar back button** restores the research screen.

The fixture server observed these paths (no cookies or headers were logged):

```text
GET /research_demo                       # readiness check
GET /configurations/ios_v1.json
GET /
GET /research_demo
GET /turbo.js
GET /sandbox_accounts
```

The test never relies on the Rails process running at port 3000. That existing listener returned 404 for `/research_demo` and `/configurations/ios_v1.json` during the initial probe; this isolated fixture run does not override the parent's separately passing Rails contract tests or claim that the active listener was refreshed.

## Reproduce

From the repository root, install the small, pinned fixture-only dependency:

```sh
npm ci --prefix native/smoke --ignore-scripts --no-audit --no-fund
```

Start the fixture server in one terminal:

```sh
ruby native/smoke/server.rb
```

It exits if the port is occupied; do not terminate an unrelated listener. In another terminal, create an isolated simulator using an installed runtime/device type:

```sh
UDID=$(xcrun simctl create "FinancialTracker Public Smoke" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5)
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b

GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all \
  xcodebuild -project native/ios/FinancialTracker.xcodeproj \
  -scheme FinancialTracker -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath native/ios/build \
  -parallel-testing-enabled NO \
  -only-testing:FinancialTrackerSmokeTests/PublicFixtureNavigationTests \
  CODE_SIGNING_ALLOWED=NO test

# Clean up only the simulator created above.
xcrun simctl shutdown "$UDID"
xcrun simctl delete "$UDID"
```

Then stop the fixture server in its terminal. `-resultBundlePath native/smoke/results.xcresult` can be added to retain a local test result bundle; choose a fresh path or remove only your own previous generated bundle. The actual run used that result path and retained an ignored `native/smoke/test.log`; neither is needed for building the application.

The UI test always supplies `FINANCIAL_TRACKER_BASE_URL=http://127.0.0.1:3301` to its app launch. It must not be changed to a private-data service. Assertions use at most 20 seconds for initial content and 10 seconds for each navigation wait.

After removing the failed disposable-auth experiment from executable source, the complete default `FinancialTracker` scheme was rerun on another test-owned simulator **without any test selector/exclusion**: **1 passed, 0 failures, 11.967s, TEST SUCCEEDED**. The fixture server and test-owned simulator were cleaned up afterward.
