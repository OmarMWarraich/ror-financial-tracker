# Financial Tracker

A Rails financial-engineering showcase with a stock watchlist, fictional portfolio
analytics, private synthetic strategy mechanics, and gated read-only provider evidence.
It is not a brokerage: no real orders, funding or investment returns are produced.

The current direction is an Equibles engineering showcase with a public fictional
portfolio, private evidence screens, and fail-closed read-only Kraken monitoring.
Rails/Hotwire is the shared UI for real Hotwire Native shell projects. The iOS
shell builds and has an isolated simulator navigation smoke; Android is scaffolded
but its local JDK/SDK are missing. Actual broker execution, funding, provider-data
redistribution, native-device acceptance and distribution remain gated.

## Frontend and UI development

The desktop-first shared shell uses Avi Flombaum's
[shadcn/ui on Rails](https://github.com/aviflombaum/shadcn-rails), pinned to
`shadcn-ui` 0.0.15, with Tailwind CSS 3.4.19 (`tailwindcss-rails` 3.3.x).
Rails ERB, Sprockets, import maps, Turbo and Stimulus remain the frontend
architecture; React and a JavaScript bundler are not required.

Install and build with:

```sh
bundle install
npm ci
bundle exec ruby bin/rails tailwindcss:build
bin/dev
```

Node packages supply Tailwind's theme plugins only. The typography plugin's
selector parser is overridden to patched 6.1.5; keep this override until the
plugin removes its vulnerable exact dependency. Do not upgrade Tailwind to v4
without migrating the upstream v3 configuration and checking compatibility.
Docker development and production builds install the locked CSS dependencies
and compile Tailwind. After source changes, rebuild the Compose image; Compose
does not bind-mount this checkout or run a CSS watcher.
Only compiled Tailwind output is linked by Sprockets. SassC still compiles
the legacy Sass grid, but CSS compression is disabled because Tailwind already
minifies its modern CSS and SassC's compressor cannot parse that color syntax.

Components generated from the MIT-licensed gem are application-owned in
`app/helpers/components` and `app/views/components/ui`. The button, badge,
card and alert copies preserve HTML/data/accessibility attributes; cards are
fluid rather than the upstream fixed-width demo. Use `render_button`,
`render_card`, `render_badge` and `render_alert` for new shared patterns.
**Generators overwrite component customizations:** inspect a generator in an
isolated checkout before adding another component; never rerun one blindly.

This is an incremental Bootstrap migration. Only Bootstrap's Sass **grid**
remains; its component CSS, reboot and JavaScript are no longer loaded.
`app/assets/stylesheets/ui.css` provides a temporary Tailwind-backed vocabulary
adapter for legacy ERB classes (`btn`, `card`, `form-control`, `table`, alerts
and display utilities), plus shared form defaults. Convert remaining legacy
markup as each page is revised instead of copying long class strings.

The shell has desktop collapse, grouped navigation, a mobile focus-trapped
drawer with Escape/overlay dismissal, a native HTML profile disclosure,
keyboard focus styles and reduced-motion support. No unsupported global search
or notification inbox is shown. Existing page-specific search, private-data
gates, form names, Turbo IDs and user workflows remain intact.
Wrapped search/list fragments replace their Turbo targets rather than appending
duplicate frame IDs. Stock-search redirects target the full page so unavailable
evidence errors remain visible outside the search frame.
Flash toasts slide/fade in, remain visible for 3 seconds, then fade out over
200 ms and are removed. Manual dismissal uses the same exit animation.
Reduced-motion preferences minimize animations; Turbo caching removes stale
toasts so they do not reappear when navigating back. Inline page warnings stay
visible.

The top bar offers Light (default), Grey (charcoal) and Dark themes. Selection
is local to this browser, persisted in `localStorage`, and synchronized across
tabs and Turbo navigation. `app/javascript/theme.js` is a small, blocking
Sprockets asset before stylesheets so a saved theme applies before first paint;
it does not introduce another JavaScript pipeline. Without JavaScript the
selector stays hidden and Light remains usable. Storage failures are reported
and theme changes still work for the current page. Use semantic shadcn colour
tokens for new surfaces; avoid fixed light backgrounds in page-specific CSS.

UI validation:

```sh
npm run test:ui
bundle exec ruby test/helpers/ui_components_test.rb
bundle exec ruby bin/rails test test/integration/application_shell_test.rb
SECRET_KEY_BASE_DUMMY=1 bundle exec ruby bin/rails assets:precompile
```

## Application features

- Account registration, sign-in, and password recovery through Devise.
- Stock search from the owner's approved private Equibles evidence; shared watchlists retain identifier metadata, not a licensed customer feed.
- Personal portfolios with add/remove controls and a 10-stock limit in the tracking eligibility checks.
- User search by first name, last name, or email, with friend add/remove controls.
- Viewing other users' tracked stocks and adding them to your own portfolio.
- Turbo-driven search results, portfolio updates, and flash messages.
- Owner-only synthetic USD sandbox with bounded versioned mandates, deterministic
  fictional fills, idempotency, transactional limits and append-only audit.
- Public synthetic research-policy lab demonstrating rejection of untrusted instructions.
- Separately gated deposit-information review; no actionable funding destination or transport.

[Equibles](https://equibles.com/): stock market data API.

> **Quote timing:** A paid Equibles plan and verified rights are required. Provider plan claims do not establish the current user's entitlement or the age of a particular observation. Private evidence retains its actual timing/delay fields and refreshes only explicitly; shared watchlists are not a quote feed.

> **Data licensing:** API access is not permission to redistribute prices. Equibles excludes live/intraday quotes and historical daily prices from standard Pro distribution rights. Obtain prior written permission or an Enterprise agreement before displaying those data to end users, including through this watchlist. See the [commercial-use requirements](#commercial-use-and-data-timing) below.

## Historical US Equities Advisory Product (Superseded)

The following advisory/business roadmap is retained as historical context, not
the current backlog. The current direction in the local ignored [plan.md](plan.md)
and the implementation sections below supersede its provider migration,
commercial-launch, Next.js, and React Native assumptions. No historical roadmap
item authorizes account access, spending, publishing provider data, or trading.

**Status: historical product direction, not implemented or approved for live use.** Alpaca integration, investment recommendations, push notifications, broker order submission, and the proposed Next.js and React Native clients do not exist in this repository. The current implemented showcase is described in the feature sections below.

The intended business is a Wyoming LLC owned and operated by its Pakistan-based owner, serving eligible US-resident customers initially. Pakistani-resident customers are outside the initial target market. Entity formation does not authorize investment advice; actual ownership, operating location, customer states, and activities must be disclosed to prospective regulated partners.

### Initial Scope and Responsibilities

The initial product is **app-generated, non-discretionary investment advice with explicit user-confirmed execution**, not autonomous portfolio management. Algorithms generate recommendations; the customer decides whether to place each order. User confirmation does not remove investment-adviser obligations.

| Component | Planned responsibility | Required before launch |
| --- | --- | --- |
| Equibles | Licensed research inputs, fundamentals, corporate actions, and eligible historical/current prices. | Written confirmation of dataset coverage, commercial rights, derived signals, automated/non-display analysis, and notification use. |
| Advisory business | Customer investment profile, objectives and risk assessment, recommendation generation, portfolio constraints, explanations, disclosures, and ongoing oversight. | Appropriate adviser registration or a genuine supervised arrangement with a registered investment adviser, determined with US securities counsel. |
| Alpaca | Approved brokerage relationship, account opening and agreed KYC/AML functions, funding, custody, execution, confirmations, and statements. | Commercial approval of the entity, operating location, advisory model, customer eligibility, and allocation of responsibilities. |
| Rails API and workers | Authorization, research ingestion, versioned strategy calculations, recommendation lifecycle, order controls, audit records, and reconciliation. | Tested security, data quality, risk controls, operational monitoring, and failure recovery. |
| Next.js and React Native | Web, Android, and iOS recommendation review, user confirmation, and order-status views. | Authenticated account access and explicit order authorization. |
| Notification infrastructure | Persisted in-app inbox, Apple Push Notification service (APNs), Firebase Cloud Messaging (FCM), and web push where supported. | Delivery permissions, device-token lifecycle, preferences, deduplication, expiry, and privacy controls. |

Alpaca and Equibles are candidate brokerage and research providers, not a complete robo-advisory service. Neither supplies our advisory authorization, investment strategy, client application, or device-notification infrastructure. An advisory partner must actually oversee the service; its registration cannot simply be borrowed. Any registrations required for our own entity or personnel remain subject to review. See the [SEC's robo-adviser guidance](https://www.sec.gov/news/pressrelease/2017-52.html).

For customers connecting existing accounts, evaluate [Alpaca Connect/OAuth](https://alpaca.markets/oauth) first. Use an approved Broker API arrangement if embedded account opening or the advisory relationship requires it. Confirm the integration model with Alpaca rather than assuming OAuth permission authorizes investment advice. Customers fund their individual brokerage accounts through approved broker-supported rails; the initial product must not collect or pool investment funds in the LLC's operating account.

### Eligible Investments

Start with US-listed stocks and US-listed equity ETFs, subject to explicit instrument approval. The eligible universe is the intersection of our product allowlist, licensed Equibles coverage, and Alpaca's current account-specific trading permissions and instrument availability. A ticker appearing in either provider is not sufficient evidence of eligibility. Restrict initial trading to long-only positions without leverage; inverse, leveraged, crypto-linked, and non-equity ETFs are outside this scope.

Equibles is **not US-only**: its [dataset catalog](https://equibles.com/data) and [price documentation](https://equibles.com/docs/api/endpoints/prices) describe international listings, ETFs/funds, and options research in addition to US stocks. That broader provider coverage does not expand our launch scope. These sources do not establish a dedicated crypto-market-data feed suitable for this product; crypto remains excluded regardless of future provider support. Dataset availability also does not establish tradability or commercial-use rights.

### Recommendation, Notification, and Order Flow

1. Establish the customer advisory relationship, investment profile, consent, and approved brokerage connection before issuing personalized recommendations.
2. Ingest licensed data and record its source, market timestamp, delay, and quality. Generate a versioned recommendation with rationale, risks, proposed action, applicable account, and expiry; suppress recommendations when inputs are missing, stale, or outside the strategy's permitted timing.
3. Persist the recommendation in the authenticated in-app inbox, then enqueue a best-effort device notification. Avoid sensitive holdings, balances, or actionable order instructions on the lock screen; deep-link to the authenticated review screen.
4. On review, check recommendation validity and refresh account state, prices, buying power, existing positions, open orders, and instrument eligibility. Present current order details, estimated impact, risks, and applicable disclosures. A recommendation price is not a guaranteed execution price.
5. Require explicit confirmation of the displayed order. Receiving, opening, or dismissing a notification is never order authorization. Expired or materially changed recommendations require a new review and confirmation; no response means no order.
6. Submit through the approved Alpaca integration with durable duplicate-order prevention. Reconcile timeouts before resubmitting; track acceptance, partial fills, rejection, cancellation, and final execution separately. Keep an auditable record of advice, notification attempts, user authorization, and broker outcomes.

Notifications are near-real-time, best-effort alerts, not guaranteed delivery or execution. Devices can be offline, permissions revoked, or operating systems can delay delivery. The inbox is the durable reference, and a delayed alert must not revive an expired recommendation. Broker order events, rather than notification delivery, determine execution status. This user-review workflow is not suitable for latency-sensitive or high-frequency strategies.

### Commercial Use and Data Timing

Provider information was reviewed on **November 3, 2026**; verify current contracts and documentation before implementation or launch.

- [Equibles pricing](https://equibles.com/pricing) and [price documentation](https://equibles.com/docs/api/endpoints/prices) distinguish Plus's 15-minute delayed US quotes from Pro's real-time US quotes. Intraday snapshots are not a guaranteed streaming feed or historical intraday candle service. Match strategy frequency to measured freshness, request quotas, historical depth, and a contracted delivery mechanism; do not describe delayed or end-of-day inputs as real-time merely because the alert is sent immediately.
- [Equibles Terms, Section 6](https://equibles.com/legal/terms#pro-distribution-rights), exclude live/intraday prices, historical daily prices, options data, and FINRA data from standard Pro end-user distribution rights. Obtain written consent or an Enterprise agreement for restricted data. Explicitly scope derived recommendations, automated/non-display processing, push notifications, historical storage/backtesting, and first-party Rails API delivery to web/mobile clients. Do not assume a derived signal bypasses source restrictions.
- Attribute permitted Equibles data close to its presentation, for example "Data by Equibles" with the required followable link. Do not expose a downstream data API, bulk feed, or export without separate rights. End-user market-data entitlements apply independently to any data obtained from Alpaca.
- Validate corporate-action adjustments, point-in-time inputs, missing history, delistings, strategy risk limits, and realistic costs/slippage before relying on backtests. Agree broker and data-provider outage behavior, monitoring, and a trading kill switch before live use.
- Complete securities counsel review, the required advisory arrangement, Alpaca production approval, data licensing, paper-trading validation, privacy/security review, and operational readiness before distributing live personalized advice or enabling real-money orders. No such approval or agreement is represented by this roadmap.

### Deferred Asset Classes and Capabilities

These are future evaluation areas, not supported portfolios, scheduled releases, or promised provider capabilities. Do not generate advice or enable orders for them in the initial product.

| Future area | Deferred work and dependencies |
| --- | --- |
| Non-US equities and international portfolios | Listing/currency identity, licensed coverage, FX, market calendars, broker access, tax, and jurisdiction review. |
| Bonds, Treasuries, fixed-income ETFs, mutual funds, and cash-management products | Product-specific data, valuation/risk models, account permissions, liquidity, and disclosures. |
| Options, futures, commodities, and foreign exchange | New data licenses, strategy validation, derivatives-specific permissions, broker capabilities, and regulatory analysis. |
| Crypto, tokenized assets, and crypto-linked funds | Separate custody, market data, execution, licensing, risk, and regulatory work; explicitly excluded for now. |
| Margin, short selling, and leveraged/inverse products | Additional suitability, borrowing, exposure controls, account permissions, and risk disclosures. |
| Autonomous discretionary rebalancing and multi-broker management | Separately approved advisory authority, mandates, supervision, allocation/reconciliation, and broker agreements; not enabled by current per-order consent. |
| Retirement/tax-advantaged accounts and non-US customers | Account-specific advice and tax obligations, customer eligibility, agreements, and jurisdiction-specific approvals. |

## Stack

- Ruby **3.3.0**, Rails **7.1.3.4**, and Bundler **2.5.6**, as recorded in the lockfile.
- PostgreSQL with Active Record.
- Puma, Devise, Turbo, Stimulus, and importmap-rails.
- Bootstrap 5, SassC, Sprockets, and Font Awesome.
- Minitest, with Capybara/Selenium configured for Chrome system tests.

See [Gemfile](Gemfile) and [Gemfile.lock](Gemfile.lock) for dependencies.

## Local Docker Compose (Recommended)

[compose.yml](compose.yml) runs Rails, Sidekiq, PostgreSQL 16.15 and Redis 7.4.12.
PostgreSQL and Redis images are digest-pinned; the application keeps Ruby 3.3.0
and Rails 7.1.3.4. Docker Desktop with Compose v2 or newer is required.

```sh
ruby bin/compose-env
docker compose --env-file .env.docker config --quiet
docker compose --env-file .env.docker build web
docker compose --env-file .env.docker up -d --wait web worker scheduler
```

Open <http://127.0.0.1:3000/portfolio_demo>. Only the web port is published,
on loopback; PostgreSQL and Redis are reachable only inside the Compose network.
Set `WEB_PORT` in the ignored `.env.docker` before startup if 3000 is occupied.
Existing host PostgreSQL/Redis services and databases are not changed or imported.
The one-shot `prepare` service waits for PostgreSQL, runs `db:prepare`, and must
succeed before web/worker startup. Health checks verify PostgreSQL readiness,
Redis PING, Rails `/up`, and this worker's actual Sidekiq heartbeat.
The retention scheduler has its own successful-enqueue heartbeat. Compose
explicitly opts into development HTTP for exact loopback/emulator hosts because
Docker forwards desktop requests from its bridge address. This opt-in never
applies in production, does not trust forwarded headers, and does not permit
arbitrary LAN hosts. The web port must stay bound to loopback; devices/LAN need
reviewed HTTPS rather than expanding that exception.

[bin/compose-env](bin/compose-env) exclusively creates an ignored mode-0600
`.env.docker` with independently generated database/session/encryption secrets.
It refuses to overwrite an existing file. **Keep and securely back up those
original secrets with the named volumes**: changing the database password does
not reset an initialized database, and losing encryption secrets makes encrypted
records unreadable. Never print interpolated `docker compose config` output;
use `config --quiet`. Secrets, local plans, host credentials and stored uploads
are excluded from the build context.

```sh
# Separate financial_tracker_test database; test Active Job adapter and fake providers.
docker compose --env-file .env.docker --profile test run --rm test
docker compose --env-file .env.docker logs --tail 100 web worker scheduler
docker compose --env-file .env.docker stop
docker compose --env-file .env.docker up -d --wait web worker scheduler
# Remove containers/network but preserve all named volumes.
docker compose --env-file .env.docker down
```

Do not use `down -v` or delete `.env.docker` as a routine reset. PostgreSQL's named
volume mounts its verified `/var/lib/postgresql/data`; Redis persists AOF under
`/data`; application uploads use a separate storage volume. The code is built
into the image, not bind-mounted: after changing it, rebuild and recreate web
and worker/scheduler with `docker compose --env-file .env.docker up -d --build --wait web worker scheduler`.

Sidekiq uses `REDIS_URL`, concurrency 5, and `maintenance`/`default` queues.
Each process has a five-connection database pool. Redis is dedicated to queues,
with `noeviction`, AOF enabled, and `appendfsync everysec`; it is not an evictable
cache. Jobs are **at-least-once**, not exactly-once. Recent queue writes can still
be lost on Redis failure; a named volume is not a backup or an execution outbox.
No trading, broker refresh, or Sidekiq Web UI is enabled by this setup.
The only periodic work is argument-free Equibles retention maintenance, enqueued
every five minutes by a separate restartable scheduler. Enqueue failures terminate
it explicitly; a healthy heartbeat is written only after successful enqueue.

The safe follow-on [ExpireEquiblesEvidenceJob](app/jobs/expire_equibles_evidence_job.rb)
reuses the existing retention policy under row locks and rechecks current rights
and original deadlines. It is idempotent, has no arguments or provider requests,
and does not decrypt credentials. In addition to scheduled cleanup, enqueue it explicitly when needed:

```sh
docker compose --env-file .env.docker exec -T web \
  bundle exec ruby bin/rails runner 'ExpireEquiblesEvidenceJob.perform_later'
```

Scheduling is best effort, **not a wall-clock deletion guarantee**. Access and
explicit refresh still enforce retention independently. A real argument-free
job was queued while the worker was stopped; its synthetic database row and
Redis queue survived database/queue container recreation, and the restarted
worker purged the evidence. Synthetic records and the smoke-test marker were
removed afterward. No actual provider account or credential was exercised.

Validated locally: health checks, HTTP demo/auth boundaries, isolated test DB,
volume persistence through PostgreSQL/Redis container recreation, worker restart,
eager loading, and the final production image build. Public image pulls required
a session-only credential-free Docker configuration because the local credential
helper stalled; existing Docker settings were not changed.

## Local Setup (Without Containers)

Run the following commands from the repository root.

### Prerequisites

Install Ruby 3.3.0, a running PostgreSQL server, a JavaScript runtime such as Node.js for ExecJS/asset compilation, and native build tools for gems such as `pg` and `sassc`. PostgreSQL development headers and `pg_config` must be available when compiling `pg`.
Schema persistence uses SQL to retain append-only sandbox triggers; use PostgreSQL
client tools compatible with your server. Containers install verified PostgreSQL
16 client packages from the official signed PGDG repository. The canonical
[db/structure.sql](db/structure.sql) is generated against the container's PostgreSQL
16 server; do not replace it with a Ruby schema that drops triggers.

The default database configuration connects over a local socket using your operating-system username. That PostgreSQL role must exist and have permission to create databases. Adjust [config/database.yml](config/database.yml) if your local setup uses a different role, password, or host.

### Install Dependencies

```sh
gem install bundler -v 2.5.6
bundle install
```

The committed lockfile includes Linux and Apple Silicon macOS platforms. If Bundler rejects another platform, add it before installing:

```sh
bundle lock --add-platform "$(ruby -e 'puts Gem::Platform.local')"
bundle install
```

This updates the lockfile; review that change before committing it.

### Credentials

Obtain the existing Rails master key from the project maintainer and place it in `config/master.key`, or supply it through `RAILS_MASTER_KEY`, to decrypt the committed [config/credentials.yml.enc](config/credentials.yml.enc). Never commit the key or API tokens.

### Equibles Private Evidence and Entitlements

The application no longer uses a global `EQUIBLES_API_KEY` or the developer's
Rails-credentials subscription as a shared user feed. Existing unrelated Rails
credentials/master keys must not be replaced. Each owner supplies an independently
permitted API key through `/equibles_evidence`, only after encryption and the
operator's actual subscription/rights verification are configured.

[config/equibles_entitlements.yml](config/equibles_entitlements.yml) defaults to
no approved users. An operator may add the following **only after obtaining the
underlying evidence**, using the actual owner ID and approval reference:

```yaml
shared:
  verified_users:
    "ACTUAL_USER_ID":
      approval_reference: "Actual written permission/account verification reference"
      subscription_verified: true
      paid_quotes: true
      automated_read: true
      private_display: true
      cache_storage: true
      daily_request_budget: 10
      retention_seconds: 3600
      freshness_seconds: 900
      # Optional approval expiry; use the actual reviewed expiry, not this example.
      expires_at: "2026-12-01T00:00:00Z"
```

All five approvals must be exactly `true`. Daily request budget is an integer
1-100; retention/freshness are integers 1-86400 seconds. These sample limits are
not subscription entitlements. Missing/unknown approvals disable real-data
features; synthetic demonstration remains independent.
Expired/malformed approval expiry disables access. Stored evidence retains its
original retention/approval deadline even after renewal; shortened retention or
revoked private-display rights cannot be bypassed by an older snapshot.

The private screen supports authenticated `GET` status, `PATCH` key setup,
explicit `POST /equibles_evidence/refresh` with one ticker, and `DELETE` disconnect.
Credential changes/disconnect require the current application password. Mutations
are CSRF protected; HTTPS is required except private loopback development.
Keys use the three deployment encryption secrets documented below; stored keys
are never redisplayed and private responses use `no-store`. Equibles quote
snapshots are owner-scoped JSONB, not Rails-encrypted attributes; secure database
storage and backups separately. Kraken account payloads are encrypted.

The [client](app/services/equibles_client.rb) uses standard HTTP/JSON libraries,
Bearer authentication, bounded five-second timeouts and zero retries.
The new evidence refresh makes **one** `GET /v1/stocks/{ticker}/quote` request.
The older direct `lookup` method retains its two-request quote/screener contract
for compatibility tests, but user-facing watchlist lookup uses only the owner's
approved retained evidence and makes no implicit network call.
Both legacy stock-list and search-result price cells explicitly say
**Unavailable**, including for old persisted prices, nulls and zeros. Licensed
quotes belong only on the owner's permitted private evidence screen.

Normalized evidence distinguishes exact provider/instrument identity, product,
currency, decimal price, provider observation time (unknown if absent), receipt
time, session/observation metadata, delay, quality and entitlement reference.
Unknown timing is never labelled real-time. Malformed/mismatched, stale, quota,
authentication and transport failures are explicit; no fictional fallback replaces
failed evidence and retained receipts are not rewritten as fresh observations.

Database locking provides per-user UTC-daily conservative quota accounting and
60-second refresh deduplication. Failed attempts consume the bounded local budget;
this is not Kraken's quota or the provider's authoritative shared-account allowance.
Retention purges on access/refresh, not a scheduled background job. History,
corporate actions, backtesting, AI processing, screenshots/recordings, native/API
delivery, hosted display and redistribution require separate rights confirmation;
none is implied by these private-display configuration flags.

Official reference: [REST API](https://equibles.com/docs/api), [authentication](https://equibles.com/docs/authentication), [paid quotes](https://equibles.com/docs/api/endpoints/prices), [company screener](https://equibles.com/docs/api/endpoints/capital), and [errors and limits](https://equibles.com/docs/api/errors).

#### C01-C03 verification review (2026-11-07)

An explicitly authorized, read-only exercise used eight HTTPS requests, with
bounded timeouts, no retries, no redirects and no writes to the provider.
The key stayed in the ignored local environment file and was sent only in the
authorization header. No raw quotes, prices, corporate-action amounts, credentials,
account identifiers or account-specific quota counters were saved in this report
or the shared knowledge store. This exercise did not install a global key in
the application or approve an owner in the entitlement configuration.

**C01: paid quote capabilities verified; billing-plan identity still pending.**
Single-stock AAPL, exact class-share BRK-B and ETF SPY quote requests all
returned HTTP 200 with matching identities and USD currency. Observed quote
fields were `ticker`, `currency`, `price`, nullable `bidPrice`/`askPrice`, `asOf`,
`sessionDate`, `expectedSessionDate`, `stale`, `ageSeconds` and `delayed`.
The samples were marked delayed and carried source/session timestamps; they
are not real-time evidence. A successful paid endpoint and quota headers
establish capabilities, not the exact billing-plan name or its expiry.
The reviewed public OpenAPI exposes no account/subscription inspection route;
confirm the named subscription and renewal/expiry privately in the owner's
billing dashboard or with provider support.

**C02: documented contracts and bounded account coverage samples verified.**

| Surface | Verified result / boundary |
| --- | --- |
| Daily prices | AAPL bars from November 2021 returned HTTP 200 with `date`, OHLC, `adjustedClose` and `volume`, plus pagination metadata. |
| Weekly/monthly | Both intervals returned HTTP 200, adding `periodStart` and `partial`. A bounded monthly query returned 61 observations from 2021-11-30 through 2026-11-06 with `hasMore: false`. This verifies that sample window, not maximum provider history or coverage of every instrument. |
| Dividends | AAPL returned HTTP 200 with `exDate`, `amountPerShare`, `currency`, `recordDate` and `paymentDate`. These are stored declared distributions, not guaranteed completeness. |
| Splits | AAPL returned HTTP 200 with `effectiveDate`, `numerator`, `denominator` and `priceHistoryAdjusted`. Check adjustment confirmation before combining series across a split. |
| Adjustments | Official documentation says OHLCV is split-adjusted, not dividend-adjusted; `adjustedClose` also reflects reconciled cash dividends but is not certified as a total-return series. These historical values are not automatically point-in-time backtest inputs. |
| Limits | Published Free/Plus/Pro allowances are 100/10,000/100,000 requests per UTC day, shared by REST and MCP. Counted responses expose `X-RateLimit-Limit`, `-Remaining` and `-Reset`. Accepted 400/403/404 responses also count; 5xx failures return their allowance. Daily-price pagination allows at most 500 rows; batch quotes at most 25 symbols. |
| Timing/session | Published US Plus quotes are 15-minute-delayed SIP; Pro is real-time SIP. `asOf` is source time, not receipt time; session dates and `stale` remain separate. Daily-bar dates do not establish intraday execution times or a complete exchange calendar. |
| Streaming | The reviewed price documentation describes snapshots, not historical intraday candles. No streaming/WebSocket route is published in the reviewed REST OpenAPI. Do not invent a streaming integration or interpret this as proof that no separately contracted service exists. |
| Coverage | Official docs include additional `MIC:TICKER` listings and listing currencies. Only the USD US-listing samples above were exercised; the current adapter intentionally still rejects other currencies and MIC-qualified symbols. |

Sources: [price contracts](https://equibles.com/docs/api/endpoints/prices),
[coverage](https://equibles.com/docs/data),
[OpenAPI](https://api.equibles.com/openapi/v1.json),
[plans](https://equibles.com/docs/rate-limits),
[pricing](https://equibles.com/pricing) and
[error/counting rules](https://equibles.com/docs/api/errors).

**C03: terms reviewed; required account-specific permissions remain blocked.**
The current [terms, sections 5-6](https://equibles.com/legal/terms) grant active
Pro subscriptions conditional end-user distribution of eligible data with
visible Equibles attribution, but expressly exclude live/intraday quotes,
historical daily prices, options data and FINRA data from that general grant.
Those restricted datasets need prior written consent or an Enterprise agreement
for redistribution or presentation to end users. Even the general Pro grant
does not permit a downstream API, feed, database or bulk dataset service.
API access, a plan label, or the successful probes above do not establish these
permissions.

Before enabling retained private evidence, obtain provider confirmation covering
the exact subscription, datasets, personal automated/non-display reads, private
application display, caching and backup retention/deletion periods. Separately
ask about backtesting, derived analytics, third-party AI inference versus model
training, public screenshots/recordings, native/mobile delivery, hosted end-user
display, downstream API access and redistribution; record exclusions and any
attribution/expiry conditions. Use [provider support](https://equibles.com/tickets)
or [support@equibles.com](mailto:support@equibles.com), without including the API
key. No ticket was submitted and no missing permission was assumed.
Until that evidence and the actual owner are established, the empty approval
configuration and all history/AI/distribution/trading gates remain unchanged.

### Prepare the Database and Start Rails

```sh
ruby bin/rails db:prepare
ruby bin/rails server
```

Open <http://localhost:3000> and register an account. The default database names are `myapp_development` and `myapp_test`. [db/seeds.rb](db/seeds.rb) currently contains no sample records or preconfigured accounts.

Commands above invoke the Rails binstub through Ruby so they also work when its executable bit is missing. [bin/setup](bin/setup) provides an automated environment refresh, but its direct calls to other binstubs require those scripts to be executable.

## Usage

- **My Portfolio** (`/my_portfolio`): search approved owner evidence and manage tracked identifiers; a watchlist is not a holdings ledger.
- **Equibles Evidence** (`/equibles_evidence`): private, explicitly refreshed quote evidence; disabled until rights and encryption are configured.
- **Private Connections** (`/broker_connections`): separately gated owner-only Kraken read monitoring, never trading authority.
- **My Friends** (`/my_friends`): search registered users and manage your friends list.
- **User Portfolio** (`/users/:id`): inspect another user's tracked stocks.
- **Health Check** (`/up`): Rails boot health endpoint, not a check of database or quote-provider connectivity.

See [config/routes.rb](config/routes.rb) for the complete route definitions.

## Portfolio Proof of Concept

With the existing Rails environment configured, start `bundle exec ruby bin/rails server`
and open `/portfolio_demo`. This public demo is deliberately isolated from private
portfolios: it collects no account credentials, writes no holdings, and makes no
Equibles, ALVIS, or Kraken requests.

It demonstrates fictional USD holdings, decimal valuation/cost basis/unrealized
gain/loss, allocation and a disclosed concentration threshold. Use the scenario
selector to exercise missing prices, missing cost basis, and an empty portfolio.
Missing evidence is shown as unavailable rather than a fabricated complete total.
Static sample prices are not live quotes or historical performance.

The holdings table includes original quantities, unit costs, cost bases, observed
prices, timestamps, values, and allocation. Formula/provenance explanations and
accessible architecture/request-flow diagrams accompany a sanitized integration
walkthrough. Explicit loading/provider-error scenarios demonstrate unavailable
states without network calls or a successful-looking fixture fallback. Company,
sector, chart/history, performance, and benchmark features remain visibly gated
on supported fields, classifications, licensed history, and methodology.

The screen is shared Rails/Hotwire UI intended for **Hotwire Native iOS and Android
apps**, not a claim that responsive web equals a native application. Shell
builds/navigation and the remaining acceptance gates are documented below.
Real account approvals and broker trading are not established by this demo.

## Private Synthetic Strategy Sandbox

Sign in and open `/sandbox_accounts`. Create a separate fictional USD account
with positive opening cash up to $10,000 and your current application password.
It cannot connect to Equibles, Kraken, ALVIS or a model, and does not share the
real monitoring connection. No funding, deposits, reset, shorting or leverage exists.

The fixed declarative `trend-v1` rule compares two original fictional observations:
`rise-v1` buys, `fall-v1` sells existing inventory, and `flat-v1` holds.
These are **synthetic mechanics scenarios**, not licensed historical backtests,
prospective broker paper fills, US-listed instruments, performance or live returns.
Fixture loading and its 15-minute validity window describe the simulation, not
market observation freshness. No uploaded code or caller/provider/model price is accepted.

Create a draft mandate with all five positive limits (capital, per-fill notional,
integer quantity, exposure, loss) and an expiry within 24 hours. Limits are never
unlimited when missing; capital cannot exceed $10,000, dependent monetary limits
cannot exceed capital, and quantity is 1-100. Password-confirm activation/resumption.
Only one mandate is active per account. Draft can activate or revoke; active can
pause or revoke; paused can resume or revoke; revoked cannot reactivate.
Expiry blocks new evaluations. Pause/revoke never liquidates existing holdings.

Account row locks serialize limits, reservations, fills and revocation. Stable
owner-bound UUID request identities return the original result on retry rather
than duplicating fills. Synthetic adverse slippage is 0.1%; the fee is 0.1%,
rounded upward to cents. Cash, inventory, fee-inclusive capital/exposure and
projected loss checks run deterministically outside any model.
The screen shows mandate/version/environment, fictional holdings/cost basis,
recent fills, provenance and audit events.

Orders/events are append-only in PostgreSQL as well as the application. Ordinary
account deletion is explicitly blocked for sandbox owners; a reviewed retention/
closure workflow remains unavailable. Do not treat this local audit design as
immutable against a database administrator. Real execution still needs licensed
history, strategy approvals, broker identity/product permissions, a durable
outbox/reconciliation, partial-fill/ambiguous-submission recovery, calendars,
separate credentials, paper acceptance and regulatory/live release gates.

## Optional Deposit-Information Review

`/deposit_information` is an authenticated owner-only review/status screen.
Its password-confirmed check makes **no Kraken request** and never grants authority.
[config/kraken_deposit_information.yml](config/kraken_deposit_information.yml)
defaults off with no approved owners; even a local review entry cannot activate
an operational adapter. No deposit key, address, payload or funding credential
is collected or stored.

Official legacy contracts and exact key/account/scope/expiry and monetary fields
have offline validators. Legacy `DepositAddresses` does not explicitly identify
the asset/network or whether a memo/tag is mandatory, so no actionable destination
is shown. Missing minimums/fees never become zero, and valid-looking addresses
are still non-actionable. Funding Beta needs its own review; this is not a claim
that it cannot support the feature. A future adapter must independently verify
the exact owner/account/product/asset/network and force address creation off.
Deposit-information rights do not authorize bank debits, wallet transfers,
withdrawals, AI funding or conventional securities funding.

## Hotwire Native Clients

See [native/README.md](native/README.md) and the reproducible
[native smoke evidence](native/smoke/README.md).

- iOS: actual HotwireNative 1.3.1 project at
  [FinancialTracker.xcodeproj](native/ios/FinancialTracker.xcodeproj), built with
  Xcode 26.5 / Swift 6.3.2. Four URL-policy tests and an isolated simulator
  fixture-navigation smoke pass; native push/back and external-link rejection
  were exercised, not merely a responsive-browser preview.
  A separate real-Rails anonymous smoke passed protected-route redirects and
  public research navigation. The signed-in follow-up stopped after two UI-test
  selector/focus failures: no successful signup, sign-in, sign-out or authenticated
  session continuity is claimed. See the [disposable Rails smoke record](native/smoke/disposable-rails.md).
- Android: actual Hotwire 1.4.0 Gradle project and wrapper are present. Build
  validation stops at missing Java/JDK and Android SDK; no Android build/device
  success is claimed.
- Both consume public versioned `/configurations/ios_v1.json` and
  `/configurations/android_v1.json`, with bundled defaults. Configuration changes
  navigation, not authorization. Rails sessions and password checks remain required.
- Local iOS simulator uses `127.0.0.1:3000`; Android emulator uses
  `10.0.2.2:3000`. Current development clients reject cross-origin navigation and
  invalid/non-loopback configuration. Real-device/LAN/remote access needs reviewed
  HTTPS, not a public tunnel or broker-key relay.
- No custom bridges, execution/scheduling on phones, store submission or real-device
  approval is implied. Authentication/session, recovery and private-device acceptance
  must be recorded separately from public fixture navigation.

```sh
swift test --package-path native/ios/URLPolicy
ruby native/test_configuration.rb
# Once an appropriate JDK and Android SDK are installed/configured:
cd native/android && ./gradlew :app:testDebugUnitTest :app:assembleDebug
```

## Private Connections and Read-Only Kraken Monitoring

`/broker_connections` is authenticated and owner-scoped; it never inherits social
watchlist sharing. Setup, disconnect, and elevation-review requests require the
current **application** password. Five failed confirmations lock sensitive actions
for 15 minutes without imposing a historical MFA migration on ordinary sign-in.
Elevation is a review request only: no endpoint activates paper/live execution,
orders, cancellations, funding, or transfers.

Connections use the existing PostgreSQL database and Rails encrypted attributes.
Set these independently generated secrets in the runtime environment or a secret
manager, separately from the database, before accepting credentials:

- `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`
- `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`
- `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`

Generate deployment-specific values with `bundle exec ruby bin/rails db:encryption:init`;
do not commit its output, reuse the test values, or replace the existing Rails
credentials/master key. Back up encryption keys securely; losing them makes stored
credentials and evidence unreadable. Production requires HTTPS; only private
loopback development may use HTTP.

Monitoring is **disabled by default** in [config/kraken_monitoring.yml](config/kraken_monitoring.yml).
Before enabling it, separately verify the actual owner's product/geography
eligibility and developer terms, then record an expiring owner-specific approval
reference there. Do not treat this configuration as regulatory approval. No real
account exercise was performed as part of implementation.

The narrow [adapter](app/services/kraken_read_only_client.rb) permits only:

| Operation | Endpoint | Required permissions |
| --- | --- | --- |
| Inspect key/account/expiry | `POST /0/private/GetApiKeyInfo` | No additional permission |
| Balances | `POST /0/private/Balance` | `query-funds` |
| Optional latest 50 trades | `POST /0/private/TradesHistory` | Additionally `query-closed-trades` |

Scope inspection happens before balance/history requests on **every refresh**.
Permissions must exactly match the selected features: unknown, unverifiable,
extra read scopes, order/cancel, deposit, withdrawal, Earn, export, and WebSocket
permissions are rejected. No write operation is probed to check permissions and
there is no arbitrary endpoint proxy. Signed POST queries remain reads by their
operation semantics, not because of their HTTP method.

Use a new dedicated key per connection; a unique retained fingerprint prevents
cross-user key reuse. Row locking serializes per-key nonce generation, refresh,
and disconnect across processes. Refresh is explicit, at most once per minute,
with bounded timeouts and **zero automatic retries** (at most three requests with
history, two without). Monitoring requests remain synchronous; they do not enqueue
provider work or use an executor. The shared Sidekiq/Redis runtime handles retention
maintenance separately.
Rate-limit/provider failures are visible; previous evidence keeps its real receipt
time and a failed/stale indication. Balance source time stays unknown; trade
timestamps remain source times.

Account identity from key inspection is pinned, credentials are never redisplayed,
and application expiry is 30 days or earlier provider expiry. Disconnect waits
for an in-flight read, removes secrets and retained account evidence, and prevents
later work from reactivating the connection. The owner must also revoke the key
at Kraken; reconnecting requires a new key. Inactive/revoked/unsafe-scope keys
cannot sync.

Kraken Exchange balances are **not conventional US stock brokerage holdings**.
Provider asset/pair IDs are retained without Equibles ticker matching. All current
exchange assets are explicitly unclassified/unsupported for equity analytics and
the strategy universe; quantities are not presented as USD portfolio values.
Recent trades are not a complete ledger or investment performance calculation.
xStocks are geographically restricted tokenized exposure, not underlying share
ownership. Conventional securities brokerage API availability and actual account
eligibility remain unverified; unsupported does not mean an empty or zero account.

Official contracts checked 2026-11-05:
[key inspection](https://docs.kraken.com/api-reference/account-data/get-api-key-info),
[permissions](https://docs.kraken.com/exchange/guides/rest/api-keys),
[authentication](https://docs.kraken.com/exchange/guides/rest/authentication),
[Spot OpenAPI](https://docs.kraken.com/openapi/spot-rest.yaml), and
[xStocks differences](https://support.kraken.com/articles/getting-started-with-xstocks).

## Synthetic Research Policy Lab

Open `/research_demo` for an original-fixture, deterministic structured-observation
validator. It is not ALVIS output, a model integration, a backtest, or a recommendation.
It accepts only a versioned observe-only signal for a fictional instrument with
matching fresh synthetic citations and bounded expiry. Unknown fields, injected
instructions, endpoints, quantities, changed model/rule/policy versions, stale or
missing citations, and exhausted budgets are rejected with explicit reasons.
The fixed fictional evaluation clock is displayed; it is not real market freshness.

No uploaded documents, private accounts, credentials or provider payloads enter
this lab. It has no model tools, external inference call, order dispatch or money
movement path. The current [official ALVIS documentation](https://equibles.com/docs/alvis)
still describes browser research and author exports separately from REST/MCP.
Supported programmatic inference, ingestion rights, external-model consent,
licenses/privacy terms and real AI/paper evaluation remain gates, not inferred
from an accepted fixture.

## Project Knowledge Retrieval

Search established provider facts and current product decisions locally:

```sh
ruby bin/project-knowledge "Elvis AI"
ruby bin/project-knowledge "Kraken connection modes"
```

This dependency-free developer tool returns at most five ranked records with
sources, dates, and explicit fact/decision/open-question/implementation status.
The curated store is [config/project_knowledge.json](config/project_knowledge.json);
update existing records when decisions change. It contains no credentials,
private account data, or raw conversation history. It is lexical retrieval, not
GraphRAG or an application-facing financial research service.

### Keeping Copilot's project context current

The [repository instructions](.github/copilot-instructions.md) tell Copilot to
assess available context before each response, reuse relevant session evidence,
and retrieve only missing, uncertain, or stale facts before substantial work.
Do not repeat retrieval or other tool calls without a concrete evidence gap.
Update affected records after meaningful decisions or implementations.
Preserve record IDs, cite sources, date
updates, distinguish plans from working features, and run the knowledge tests
plus a representative query before completing a knowledge-store change.
This is curated maintenance by the working agent/developer, not automatic chat
ingestion or a background synchronization service.

A new or resumed session cannot assume its memory matches the repository.
Compare the task-relevant decisions, implementation status, sources, and
freshness already available; when their applicability is unknown, retrieve the
relevant records once and verify only unresolved details against cited sources.
This establishes sufficient context for the task, not whole-store parity or an
automatic freshness guarantee. Reconcile conflicting memory with current code
and explicit user decisions rather than silently carrying stale assumptions.

Before every authorized commit, review the staged changes against the store and
include affected knowledge updates in that same commit. If no reusable facts
change, leave records/dates untouched and note that the retrieval review required
no update. This is a review requirement, not a demand for artificial record churn
or permission to create commits.

Local Copilot agents with terminal access can run the same command; without a
terminal, they can read the JSON records directly. GitHub-hosted agents need the
instructions, JSON store, CLI, and library available in their committed/pushed
checkout. The ignored `plan.md` and `todo.md` remain local and must not be
force-added; reusable non-sensitive facts belong in the shared store.

Retrieval itself performs no network or model calls. Copilot still uses inference
for reasoning, coding, and tool orchestration, and retrieved text consumes context.
Instructions do not guarantee retrieval in every Copilot mode or inline completion.
The aim is less repeated reading/research, not guaranteed token or billing savings.

Equibles calls its built-in AI analyst **ALVIS** (sometimes transcribed as Elvis
or Alvish). See the [official ALVIS documentation](https://equibles.com/docs/alvis).
The browser feature is verified; a supported ALVIS inference API is not yet
verified. Do not confuse Equibles REST/MCP data access with an ALVIS chat API.

The [current direction in plan.md](plan.md#current-direction-demonstrate-engineering-not-launch-a-trading-business)
supersedes earlier planned-product descriptions in this README and the historical
appendix in the plan. Retrieval tooling does not implement those planned features.

## Tests

Current container verification on 2026-11-05:

```sh
docker compose --env-file .env.docker --profile test run --rm test
# 207 tests, 2,742 assertions; zero failures, errors or skips; two test workers.
docker compose --env-file .env.docker exec -T web bundle exec ruby bin/rails zeitwerk:check
```

The final production image also builds and boots with an ephemeral smoke secret.
Secret-generation tests verify mode 0600, independent values, no secret output,
and refusal to overwrite existing secrets. Retention tests cover current rights,
original retention deadlines, preserved fresh evidence, idempotency, and no
provider requests. The expanded suite also covers owner isolation, password
approval, synthetic ledger concurrency/idempotency/expiry, SQL append-only
protections, explicit account-closure refusal, structured-research rejection,
disabled deposit contracts and native navigation metadata. Container
recreation/restart verification is described above.

A-E baseline, before the container/maintenance additions, verified on 2026-11-05
with Ruby 3.3.0, Rails 7.1.3.4 and Minitest 5.27:

```sh
RAILS_ENV=test bundle exec ruby bin/rails test --seed 12345
# 151 tests, 2,220 assertions; zero failures, errors or skips.
RAILS_ENV=test bundle exec ruby bin/rails zeitwerk:check
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bundle exec ruby bin/rails assets:precompile
```

Eager loading and production asset compilation pass. Existing RubyGems constant
and Rack status-name deprecation warnings remain. Browser checks and screenshots
use original fictional fixtures, not real provider accounts. Native build and
simulator evidence is recorded separately above.

### Original-fixture walkthrough captures

These captures are engineering demonstrations, not provider data, research
recommendations, performance evidence or live account screenshots:

- [Desktop portfolio](docs/showcase/portfolio-desktop.png)
- [Narrow portfolio](docs/showcase/portfolio-mobile.png)
- [Research-policy rejection](docs/showcase/research-policy.png)
- [Private synthetic sandbox](docs/showcase/synthetic-sandbox.png)

The local browser walkthrough exercised draft creation, password-confirmed
activation, a fictional fill, pause and terminal revocation. The sandbox has no
page overflow at a measured 320 CSS pixels; its wide fills table scrolls within
an accessible region. The optional deposit-review form also fits that width.
Its disposable database is separate
from normal development data. No paid/credentialed provider request, real broker
paper exercise, funding, public deployment or live trade was performed.

Outstanding A-E gates: actual Equibles subscription and use/display/retention/
distribution permissions; strategy-specific freshness/rights; Kraken owner
product/geography/developer-terms review, conventional securities API access and
actual xStocks eligibility; and future mandate/live/recovery-specific step-up
workflows. These are not marked completed or enabled by the passing fake-based
tests. Use the private-screen configuration instructions above; never substitute
a role toggle or an unverified key for these approvals.

With PostgreSQL running and a separate test database configured:

```sh
RAILS_ENV=test ruby bin/rails db:prepare
ruby bin/rails test
ruby bin/rails test test/models/stock_test.rb test/controllers/user_stocks_controller_test.rb
ruby bin/rails test:system
```

The Equibles client tests can run without PostgreSQL or a live API key:

```sh
bundle exec ruby test/services/equibles_client_test.rb
```

The standalone project-knowledge tests also need no database or network:

```sh
bundle exec ruby test/lib/project_knowledge_test.rb
```

The proof-of-concept checks exercise exact analytics and real Rails requests
without fixtures, data writes, external APIs, or the Rails test-case runner:

```sh
bundle exec ruby -Itest -e 'ARGV.each { |file| require_relative file }' \
  ./test/services/portfolio_analytics_test.rb ./test/integration/portfolio_demo_test.rb
```

Provider responses are stubbed; these checks do not validate a live subscription.
The model/controller regressions now cover real watchlist eligibility, duplicate
and 10-stock enforcement, owner-only removal, friend views, and authentication
rather than generated placeholder assertions. Dedicated private-connection
checks cover encrypted storage, redaction, cross-user denial, CSRF, password
step-up/lockout, stale evidence, expiry/revocation, nonce concurrency, and
disconnect/in-flight-read coordination.

**Resolved Rails runner incompatibility:** Ruby 3.3.0 / Rails 7.1.3.4 with
Minitest 6.0.6 reproduced `line_filtering.rb:7: wrong number of arguments
(given 3, expected 1..2)`. The test dependency is now constrained to compatible
Minitest 5.27 without upgrading Rails, Devise, or assets. Sidekiq 8.0.10 uses
connection_pool 2.5 because v3 fails to parse on Ruby 3.3.0; JSON stays below v3
because Rails 7.1 still passes its removed `create_additions` option. Both Linux
platforms are locked and image bundles are frozen, avoiding runtime lockfile
rewrites by the non-root user.
After `bundle install`, the affected regression selectors pass:

```sh
bundle exec ruby bin/rails test test/models test/controllers --seed 12345
bundle exec ruby test/services/kraken_read_only_client_test.rb
bundle exec ruby test/integration/broker_connections_test.rb
```

PostgreSQL and the migrated isolated test database are required for application
tests; no real API keys are needed. Tests generate/configure fake encryption
material only inside the test process. Passing these tests is not a native-device
test or authorization for a credentialed provider/account exercise.

System tests are configured to use Chrome through Selenium, so browser-based tests require Chrome and an available compatible driver. See [test/test_helper.rb](test/test_helper.rb) and [test/application_system_test_case.rb](test/application_system_test_case.rb).

## Docker and Production

[Dockerfile](Dockerfile) builds a production image with precompiled assets and a non-root runtime user:

```sh
docker build -t financial-tracker .
docker run --rm -p 3000:3000 \
	-e RAILS_MASTER_KEY \
	-e SECRET_KEY_BASE \
	-e DATABASE_URL \
	-e REDIS_URL \
	-e ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY \
	-e ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY \
	-e ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT \
	financial-tracker
```

Export the listed secrets in your shell before running the container; never put
their values in the command, image or repository. Provider features remain
disabled until their owner-specific approval configuration is supplied.
The image explicitly invokes Ruby/Bash; no binstub chmod is needed. Use a PostgreSQL URL reachable
**from the container**; `localhost` inside the container is not your host machine.
The image does not include PostgreSQL/Redis; the entrypoint runs `db:prepare`.
Run a separate worker from the same image with
`bundle exec sidekiq -C config/sidekiq.yml`, supplying the same database,
Redis and encryption configuration. The Compose file above is local development,
not a production deployment specification.

Production forces HTTPS. Deploy behind an appropriately configured TLS-terminating
reverse proxy; the plain HTTP mapping is not a complete production deployment.
Configure production mail delivery before relying on password recovery.

Relevant runtime settings:

| Setting | Purpose |
| --- | --- |
| `RAILS_MASTER_KEY` | Decrypts Rails credentials when the key file is unavailable. |
| `DATABASE_URL` | Supplies a PostgreSQL connection URL, overriding matching database configuration values. |
| `SECRET_KEY_BASE` | Runtime session signing secret when not supplied through Rails credentials. |
| `REDIS_URL` | Dedicated Sidekiq Redis URL; defaults to loopback DB 0 outside Compose. |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | Encrypts provider credentials and Kraken payloads, not Equibles JSONB snapshots. |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | Independent Rails encryption configuration secret. |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | Independent Rails encryption key-derivation salt. |
| `MYAPP_DATABASE_PASSWORD` | Password for the default production `myapp` database role when not overridden by the connection URL. |
| `RAILS_MAX_THREADS` | Database pool size and Puma thread configuration; defaults to 5. |
| `RAILS_LOG_LEVEL` | Production log level; defaults to `info`. |

See [config/environments/production.rb](config/environments/production.rb), [config/database.yml](config/database.yml), and [bin/docker-entrypoint](bin/docker-entrypoint) for deployment behavior. The build's `SECRET_KEY_BASE_DUMMY` is only for asset precompilation, not a substitute for runtime credentials.
