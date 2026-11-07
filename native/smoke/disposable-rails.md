# Disposable-Rails cookie lifecycle attempt

## M6 chat attempt, 2026-11-07: partial, not accepted

Two new bounded XCUITest attempts used an isolated iPhone 17 Pro / iOS 26.5
simulator, an original-fixture-only account, and a loopback proxy forwarding to
the existing Rails server. Both builds succeeded; both selected chat tests
failed (exit 65) waiting for the Research chat navigation link after sign-in.
The second attempt confirmed password entry did not modify the email field, but
this does not establish authenticated session continuity. Neither reached chat
submission, keyboard/chat acceptance, background/resume, network recovery or
logout assertions. No paid/provider request occurred.

The failed experimental method was removed rather than adding an unconditional
failure or presenting an opt-in skip as acceptance. The existing anonymous smoke
test is unchanged. The proxy was stopped and only the new simulator was shut
down/deleted. Disposable accounts are removed after web acceptance. Android
also remains blocked by missing Java/SDK tooling; no licenses were accepted or
SDK/emulator downloads performed. M6-06 stays open. Browser acceptance and the
20 bundled route cases are separate evidence, not device acceptance.

## Result, 2026-11-05: failed, not skipped

This final, bounded attempt used the parent's `http://localhost:3101` server and its isolated `financial_tracker_showcase_smoke` database, not the normal Rails database or an existing account.

- New test-owned simulator: `FinancialTracker Disposable Rails Smoke 5204a739`, iPhone 17 Pro / iOS 26.5. It was shut down and deleted afterward.
- Selected test: `RealRailsSessionTests.testDisposableRailsCookieSignInAndSignOut`.
- First run failed in **9.721 seconds**: signup and the retained sign-in screen both exposed an `Email` field to XCUITest, making the selector ambiguous.
- One test-only selector refinement was attempted. The final run failed in **16.629 seconds** with **`TEST FAILED`**, exit status 65:

```text
Failed to synthesize event: Neither element nor any descendant has keyboard focus.
Event dispatch snapshot: TextField ... label: 'Email'
```

The final run successfully reached Rails sign-in and tapped the existing **Sign up** link, but failed trying to enter the fixture email. Filtering accessibility matches with `isHittable` did not reliably distinguish the retained underlying form from the active native modal's field.

**No signup form was submitted; no user or sandbox ledger was created.** There is no fixture email/account requiring removal. The test defined only an explicitly nonsecret fixture password, `synthetic-fixture-only-password`, as approved for this disposable database; it never reached password entry. No real/provider credentials or private records were accessed.

This is a fatal native UI-automation focus/selection failure, **not a passing authentication test and not proof that Rails authentication failed**. Registration, native cookie sign-in/sign-out and authenticated session continuity remain unverified. No client authentication logic, WebView injection, custom login API, bridge, Rails code or backend data was changed to work around it. The bounded attempt stopped after this refinement.

The earlier [real-Rails public/protected navigation test](rails.md) and [fixture navigation/back test](README.md) remain separate passing evidence.

## Historical attempt command — not current acceptance

The failed flow was subsequently removed from the executable UI-test source to avoid introducing an unconditionally failing test into the anonymous Rails smoke scheme. It is not skipped or presented as passing acceptance. Only this historical failure record remains; the current `FinancialTrackerRailsSmoke` scheme runs the earlier anonymous navigation test, and `FinancialTracker` runs the fixture-navigation test.

The following command records the failed attempt; its removed test selector is **not a current runnable acceptance command**:

```sh
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all \
  xcodebuild -project native/ios/FinancialTracker.xcodeproj \
  -scheme FinancialTrackerRailsSmoke -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath native/ios/build -parallel-testing-enabled NO \
  -only-testing:FinancialTrackerRailsSmokeTests/RealRailsSessionTests/testDisposableRailsCookieSignInAndSignOut \
  CODE_SIGNING_ALLOWED=NO test
```

The actual run used the ignored `native/smoke/disposable-results.xcresult` and `native/smoke/disposable-test.log`. Its assertions were fatal and its recorded result remains failed. After testing, only the test-owned simulator was deleted. No native test server/helper remains; the parent's port-3101 server was left untouched.
