# Financial Tracker

A Ruby on Rails application for maintaining a stock watchlist and following other users' portfolios. This is a tracking app, not a brokerage: it does not execute trades or record holdings, transactions, or investment returns.

The current direction is an Equibles engineering showcase with a public fictional
portfolio, private evidence screens, and fail-closed read-only Kraken monitoring.
Rails/Hotwire is the shared UI for future Hotwire Native iOS/Android shells.
Trading, funding, native builds, and public redistribution of provider data are
not enabled by these implementation slices.

## Features

- Account registration, sign-in, and password recovery through Devise.
- Stock search from the owner's approved private Equibles evidence; shared watchlists retain identifier metadata, not a licensed customer feed.
- Personal portfolios with add/remove controls and a 10-stock limit in the tracking eligibility checks.
- User search by first name, last name, or email, with friend add/remove controls.
- Viewing other users' tracked stocks and adding them to your own portfolio.
- Turbo-driven search results, portfolio updates, and flash messages.

[Equibles](https://equibles.com/): stock market data API.

> **Quote timing:** A paid Equibles plan and verified rights are required. Provider plan claims do not establish the current user's entitlement or the age of a particular observation. Private evidence retains its actual timing/delay fields and refreshes only explicitly; shared watchlists are not a quote feed.

> **Data licensing:** API access is not permission to redistribute prices. Equibles excludes live/intraday quotes and historical daily prices from standard Pro distribution rights. Obtain prior written permission or an Enterprise agreement before displaying those data to end users, including through this watchlist. See the [commercial-use requirements](#commercial-use-and-data-timing) below.

## Historical US Equities Advisory Product (Superseded)

The following advisory/business roadmap is retained as historical context, not
the current backlog. The current direction in the local ignored [plan.md](plan.md)
and the implementation sections below supersede its provider migration,
commercial-launch, Next.js, and React Native assumptions. No historical roadmap
item authorizes account access, spending, publishing provider data, or trading.

**Status: product direction only, not implemented or approved for live use.** The current application remains the watchlist described above. Alpaca integration, investment recommendations, push notifications, order submission, and the proposed Next.js and React Native clients do not exist in this repository yet.

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
docker compose --env-file .env.docker up -d --wait web worker
```

Open <http://127.0.0.1:3000/portfolio_demo>. Only the web port is published,
on loopback; PostgreSQL and Redis are reachable only inside the Compose network.
Set `WEB_PORT` in the ignored `.env.docker` before startup if 3000 is occupied.
Existing host PostgreSQL/Redis services and databases are not changed or imported.
The one-shot `prepare` service waits for PostgreSQL, runs `db:prepare`, and must
succeed before web/worker startup. Health checks verify PostgreSQL readiness,
Redis PING, Rails `/up`, and this worker's actual Sidekiq heartbeat.

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
docker compose --env-file .env.docker logs --tail 100 web worker
docker compose --env-file .env.docker stop
docker compose --env-file .env.docker up -d --wait web worker
# Remove containers/network but preserve all named volumes.
docker compose --env-file .env.docker down
```

Do not use `down -v` or delete `.env.docker` as a routine reset. PostgreSQL's named
volume mounts its verified `/var/lib/postgresql/data`; Redis persists AOF under
`/data`; application uploads use a separate storage volume. The code is built
into the image, not bind-mounted: after changing it, rebuild and recreate web
and worker with `docker compose --env-file .env.docker up -d --build --wait web worker`.

Sidekiq uses `REDIS_URL`, concurrency 5, and `maintenance`/`default` queues.
Each process has a five-connection database pool. Redis is dedicated to queues,
with `noeviction`, AOF enabled, and `appendfsync everysec`; it is not an evictable
cache. Jobs are **at-least-once**, not exactly-once. Recent queue writes can still
be lost on Redis failure; a named volume is not a backup or an execution outbox.
No trading, broker refresh, scheduler, or Sidekiq Web UI is enabled by this setup.

Validated locally: health checks, HTTP demo/auth boundaries, isolated test DB,
volume persistence through PostgreSQL/Redis container recreation, worker restart,
eager loading, and the final production image build. Public image pulls required
a session-only credential-free Docker configuration because the local credential
helper stalled; existing Docker settings were not changed.

## Local Setup (Without Containers)

Run the following commands from the repository root.

### Prerequisites

Install Ruby 3.3.0, a running PostgreSQL server, a JavaScript runtime such as Node.js for ExecJS/asset compilation, and native build tools for gems such as `pg` and `sassc`. PostgreSQL development headers and `pg_config` must be available when compiling `pg`.

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
apps**, not a claim that responsive web equals a native application. Native shells,
navigation, authentication/session integration, bridges, and device tests remain
separate implementation work. Real account connections and trading are not active.

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
history, two without). No worker, Redis, polling loop, or executor is introduced.
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

A-E baseline, before the container/maintenance additions, verified on 2026-11-05
with Ruby 3.3.0, Rails 7.1.3.4 and Minitest 5.27:

```sh
RAILS_ENV=test bundle exec ruby bin/rails test --seed 12345
# 151 tests, 2,220 assertions; zero failures, errors or skips.
RAILS_ENV=test bundle exec ruby bin/rails zeitwerk:check
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bundle exec ruby bin/rails assets:precompile
```

Eager loading and production asset compilation pass. Existing RubyGems constant
and Rack status-name deprecation warnings remain. Browser checks cover the
synthetic screen's narrow/wide layouts and keyboard interaction, not native
shells or real provider accounts.

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
