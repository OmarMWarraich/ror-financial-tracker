# Local Hotwire Native shells

These are actual native development applications, not a responsive-web substitute:

- **iOS:** UIKit `Navigator` from official **Hotwire Native iOS 1.3.1**, with native navigation controllers and modal navigation. SwiftPM pins release `1.3.1`, revision `dbc4fc0fec0d2401f0be46015793bfcb29ec07a4`.
- **Android:** `HotwireActivity`, `NavigatorHost`, and native fragment navigation from official **`dev.hotwire:core:1.4.0`** and **`dev.hotwire:navigation-fragments:1.4.0`**.

Both load the existing Rails HTML and use the Rails cookie session in their own platform WebView cookie store. Cookies are not shared with Safari/Chrome or between platforms. There are no provider credentials, model/execution code, native financial operations, or custom bridge components in these projects.

## Rails contract

Start the Rails application at port 3000 using the repository's local development instructions. Local Compose uses its development-only `LOCAL_COMPOSE_HTTP=1` transport opt-in; this is not a production or LAN HTTP setting.

| Platform | Default origin | Public JSON configuration |
| --- | --- | --- |
| iOS Simulator | `http://127.0.0.1:3000` | `/configurations/ios_v1.json` |
| Android Emulator | `http://10.0.2.2:3000` | `/configurations/android_v1.json` |

`10.0.2.2` is the Android Emulator's alias for the development machine, not a public server or a physical-device address. Android networking to a loopback-only Docker publication still needs verification on the installed emulator.

Serve each configuration with HTTP 200 and JSON content, without authentication or a redirect. Do not put account information or secrets in this public document. Both shells load bundled defaults first, then the framework's cached/fresh remote configuration. A missing remote endpoint does not prevent bundled navigation, but remote configuration is not verified until the Rails endpoint succeeds.

Rules cascade in order. The bundled configurations use:

- `settings.schema_version = 1` as application metadata; the framework does not itself enforce this field as a schema validator.
- Default `context: "default"`, `presentation: "default"`, `pull_to_refresh_enabled: false`.
- `/sandbox_accounts` and `/research_demo`, including child paths, as ordinary same-origin web screens in native navigation.
- Feature-gated `/research_chats`, including owned conversation paths, uses the
  same default web navigation; the bundled route runner now verifies 20 cases.
  M6 browser chat works with original fixtures, but signed-in native chat
  acceptance remains open; see [bounded attempt evidence](smoke/disposable-rails.md).
- `/users/sign_in`, `/users/sign_up`, `/users/password/new` as modal context.
- Android default `uri: "hotwire://fragment/web"`; **Android modal auth rules must override this with `uri: "hotwire://fragment/web/modal/sheet"`**, the official built-in bottom-sheet destination. Merely changing `context` does not select the bottom-sheet fragment.

iOS disables query-string matching; Android matches the path. Do not depend on query parameters to select these rules.

Launch always visits `/`. Login remains Rails HTML and form submission, including CSRF and same-origin redirects. A successful modal form redirect to a default-context page uses Hotwire's normal modal dismissal/navigation. The shells do not invent a login API, store passwords, force `replace_root` for every page, or change server authentication behavior. Any login/logout history reset, historical-location routes, session expiry, and cache invalidation must be implemented/tested with the Rails navigation contract; they have not been verified end-to-end here.

The frameworks add both current `Hotwire Native iOS/Android` and compatibility `Turbo Native iOS/Android` user-agent tokens; application prefix is `FinancialTracker;`. Server-side `hotwire_native_app?` support depends on the installed `turbo-rails` version. No additional backend gem was added by these projects.

## iOS

Open `ios/FinancialTracker.xcodeproj`, select the shared `FinancialTracker` scheme, and select an installed iOS simulator. Signing is not needed for a simulator. The project targets iOS 16+ and Swift 6 language mode.

From the repository root:

```sh
swift test --package-path native/ios/URLPolicy
ruby native/test_configuration.rb

xcodebuild \
  -project native/ios/FinancialTracker.xcodeproj \
  -scheme FinancialTracker -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath native/ios/build CODE_SIGNING_ALLOWED=NO build
```

If Git is configured with `safe.bareRepository=explicit`, SwiftPM fetching can fail. The successful local build used this **command-scoped** compatibility setting; it does not change global Git configuration:

```sh
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all \
  xcodebuild -project native/ios/FinancialTracker.xcodeproj \
  -scheme FinancialTracker -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath native/ios/build CODE_SIGNING_ALLOWED=NO build
```

To select another local port, add the Run scheme environment variable:

```text
FINANCIAL_TRACKER_BASE_URL=http://127.0.0.1:3001
```

Only HTTP origins on exact `127.0.0.1` or `localhost`, with an optional valid port and no credentials, path, query, or fragment, are accepted. Invalid configuration shows a local error rather than falling back to an external URL. The route decision handler rejects nonmatching origins, including changed ports. The Info.plist contains local-development transport exceptions only.

The checked-in project is sufficient to build. To regenerate it, the bounded generator dependency is Ruby gem `xcodeproj` **1.27.0**:

```sh
gem install xcodeproj --version 1.27.0 --install-dir native/.tools/gems --no-document
GEM_HOME="$PWD/native/.tools/gems" GEM_PATH="$PWD/native/.tools/gems" \
  ruby native/ios/generate_project.rb
```

`@preconcurrency import HotwireNative` is required for this Swift 6 app to consume the dependency's Swift 5 shared configuration API; configuration is performed during UIKit application startup.

## Android

Open `android/` in Android Studio with JDK **17**, Android SDK platform **35**, and an API **28+** emulator. No SDK or emulator image is downloaded by this repository.

Pinned build tooling matches the official 1.4.0 project's versions:

- Android Gradle Plugin **8.13.2**.
- Kotlin Android plugin **2.3.0**.
- Gradle wrapper **9.2.0** (`-bin`, pinned distribution SHA-256).
- Material Components **1.12.0**; JUnit **4.13.2**.
- `compileSdk` / `targetSdk` **35**, `minSdk` **28**.

```sh
cd native/android
./gradlew :app:testDebugUnitTest :app:assembleDebug
# Optional explicit local origin, e.g. after arranging emulator/adb port forwarding:
./gradlew -PfinancialTrackerBaseUrl=http://127.0.0.1:3001 :app:assembleDebug
```

The property is checked during Gradle configuration and again by `DevelopmentURLPolicy` at runtime. Only exact HTTP origins on `10.0.2.2`, `127.0.0.1`, or `localhost` are accepted; malformed URLs and external/LAN origins fail closed. Origin changes are rejected by the route decision handler. Android cleartext networking is limited to these three hosts, backup is disabled, and WebView debugging is disabled.

The wrapper scripts/JAR come from the official Gradle `v9.2.0` source tag. Wrapper JAR SHA-256: `423cb469ccc0ecc31f0e4e1c309976198ccb734cdcbb7029d4bda0f18f57e8d9`. Distribution SHA-256: `df67a32e86e3276d011735facb1535f64d0d88df84fa87521e90becc2d735444`.

## Verification and remaining gates

Locally verified on 2026-11-05:

- Xcode **26.5 (17F42)** / Swift **6.3.2**: `xcodebuild ... build` **BUILD SUCCEEDED** for the iOS Simulator, including arm64 and x86_64.
- Swift URL policy: **4 tests passed**, covering default and explicit origins, allowed app paths, invalid configuration, credentials, schemes, host and port changes.
- `ruby native/test_configuration.rb`: **16 bundled route cases passed** across iOS and Android.
- `plutil -lint native/ios/FinancialTracker/Info.plist`: **OK**.
- Built app installed and launched successfully on an iPhone 17 Pro / iOS 26.5 Simulator using `simctl`; its application process was confirmed running.
- **Separate simulator acceptance:** one XCUITest passed on a newly created, isolated iPhone 17 Pro / iOS 26.5 simulator. It loaded public synthetic fixtures, verified native navigation titles, rejected an external link, pushed `/sandbox_accounts`, and returned with the native back button. See [the distinct smoke-test evidence and reproduction instructions](smoke/README.md). No accounts, private data, or real devices were used.
- **Real-Rails follow-up:** a separate XCUITest passed against `http://127.0.0.1:3000` in another newly created simulator: anonymous protected `/` → sign-in → public `/research_demo` → protected `/` → sign-in. Signup/sign-in/sign-out were not attempted after a nonsecret input probe proved XCTest logs secure-field input. No user or ledger was created. See [the separate real-Rails evidence and authentication blocker](smoke/rails.md).
- **Final disposable-DB auth attempt:** the separately approved `http://localhost:3101` server allowed explicitly nonsecret fixture credentials. Two bounded test runs failed before signup submission: first duplicate email accessibility matches, then missing keyboard focus after a selector refinement. Final result **TEST FAILED, 16.629s**; no account/ledger was created. Native authenticated cookie lifecycle remains unverified. See [the distinct failure evidence](smoke/disposable-rails.md).
- **Default-suite regression check:** the failed disposable-auth flow was removed from executable test source, not skipped or counted as acceptance. Both schemes were rerun without `-only-testing`/`-skip-testing`: `FinancialTracker` **1 passed, 11.967s**; `FinancialTrackerRailsSmoke` **1 passed, 10.231s**. Only the earlier fixture and anonymous Rails tests execute.
- Android `./gradlew --version` stops with **Unable to locate a Java Runtime**. No JDK, Android Studio, Android SDK, `adb`, or system Gradle was found in the relevant standard locations. Android compilation, its four JUnit tests, emulator networking and runtime behavior are therefore **not verified**. The official wrapper is present, but installing an entire SDK/image was intentionally not attempted.

These are local development shells, not release-ready applications. Physical-device testing, actual login/logout/session-expiry navigation, remote configuration refresh/offline behavior, accessibility, comprehensive content/redirect isolation, distribution signing, privacy review, icons, and store submission remain unverified. No security certification is implied by URL-policy unit tests or the single public-fixture smoke. Do not point these shells at private production data or create tunnels/private screenshots for testing. Real-device/LAN work requires a separately reviewed TLS origin/configuration; arbitrary remote hosts are deliberately unsupported here.

### Workstream J acceptance scope

| Task | Native evidence / remaining gate |
| --- | --- |
| J01 | iOS native shell implemented, simulator build, public-fixture native navigation/back and real-Rails public/protected navigation verified. |
| J02 | Android native project and official dependencies implemented; build/runtime blocked by absent JDK/SDK. |
| J03 | Versioned endpoint wiring and 16 bundled route cases verified. The UI smoke requested the local synthetic configuration endpoint; it is not a Rails deployment acceptance test. |
| J04 | Rails-cookie architecture and real-Rails anonymous protected redirect verified; signup/login/logout, expiry, authorization and step-up remain unverified. A final disposable-DB dummy-credential attempt failed in UI field focus before signup; no account was created. |
| J05 | No embedded credentials or private screenshots; authenticated deep links, secure-storage needs and device revocation remain unimplemented/unverified. |
| J06 | Constraint respected: no speculative bridges or parallel React Native frontend. No concrete native bridge capability was requested. |
| J07 | Explicit loopback/emulator configuration implemented; iOS loopback verified by the isolated smoke. Android emulator connectivity remains unverified. |
| J08 | Authenticated LAN/remote pairing is deliberately not introduced; a separately approved remote-access design remains a gate if needed. |
| J09 | Constraint respected: no model, execution or scheduling code on the phones. |
| J10 | Partial: iOS fixture push/back/external-link rejection and real-Rails public/protected-root navigation verified. Session recovery, authenticated protected links and demo/private separation across both platforms remain open. |
| J11 | Partial: iOS simulator evidence exists separately from build evidence. Android simulator and all physical-device checks remain blocked/unperformed. |
| J12 | Distribution/store/privacy review remains open; no store submission or distribution signing was attempted. |

## Official references

- [iOS getting started](https://native.hotwired.dev/ios/getting-started), [iOS configuration](https://native.hotwired.dev/ios/configuration), [iOS path configuration](https://native.hotwired.dev/ios/path-configuration).
- [Android getting started](https://native.hotwired.dev/android/getting-started), [Android configuration and origin trust](https://native.hotwired.dev/android/configuration).
- [Path configuration reference](https://native.hotwired.dev/reference/path-configuration), [native navigation](https://native.hotwired.dev/reference/navigation).
- [Hotwire Native iOS 1.3.1 source](https://github.com/hotwired/hotwire-native-ios/tree/1.3.1), [Android 1.4.0 source](https://github.com/hotwired/hotwire-native-android/tree/1.4.0), [Gradle wrapper source](https://github.com/gradle/gradle/tree/v9.2.0/gradle/wrapper).
