# Financial Tracker

A Ruby on Rails application for maintaining a stock watchlist and following other users' portfolios. This is a tracking app, not a brokerage: it does not execute trades or record holdings, transactions, or investment returns.

## Features

- Account registration, sign-in, and password recovery through Devise.
- Stock search by ticker, displaying company names and paid intraday quotes from Equibles.
- Personal portfolios with add/remove controls and a 10-stock limit in the tracking eligibility checks.
- User search by first name, last name, or email, with friend add/remove controls.
- Viewing other users' tracked stocks and adding them to your own portfolio.
- Turbo-driven search results, portfolio updates, and flash messages.

[Equibles](https://equibles.com/): stock market data API.

> **Quote timing:** A paid Equibles plan is required. Plus returns 15-minute delayed US quotes; Pro returns real-time US quotes. The app rejects quotes marked stale by the provider. Prices saved with tracked stocks are snapshots and are not automatically refreshed.

> **Data licensing:** API access is not permission to redistribute prices. Equibles excludes live/intraday quotes and historical daily prices from standard Pro distribution rights. Obtain prior written permission or an Enterprise agreement before displaying those data to end users, including through this watchlist. See the [commercial-use requirements](#commercial-use-and-data-timing) below.

## Planned US Equities Advisory Product

See [plan.md](plan.md) for the current implementation roadmap: a local-first Marketstack Professional pilot, agentic AI research, and principal-only automatic trading under an approved mandate, starting in paper mode. That plan supersedes the earlier provider, frontend, and hosting assumptions below; future customer trading remains separately gated and user-confirmed. These capabilities are planned, not implemented.

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

## Local Setup

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

### Equibles API Key

Create a key in the [Equibles API key dashboard](https://equibles.com/dashboard/apikeys) and enable a Plus or Pro plan. Keep the key server-side; never commit it or include it in browser JavaScript.

Set `EQUIBLES_API_KEY` in your shell or deployment environment. For local development, create `.env` from [.env.example](.env.example) if it does not already exist, then set its `EQUIBLES_API_KEY` value to your key. An ignored `.env` placeholder is provided when setting up this migration. Load it explicitly before starting Rails:

```sh
set -a
. ./.env
set +a
```

The app does not include dotenv, so placing a key in `.env` alone does not load it. Alternatively, add this structure to encrypted Rails credentials:

```yaml
equibles:
  api_key: eq_your_api_key
```

Edit credentials with your configured editor, for example:

```sh
EDITOR="code --wait" ruby bin/rails credentials:edit
```

`EQUIBLES_API_KEY` takes precedence over `equibles.api_key` in Rails credentials. Do not replace the shared credentials or generate a new master key for the existing encrypted file. The old `iex_client` entries are no longer read and can be removed through the credentials editor once no other integration needs them.

The [Equibles client](app/services/equibles_client.rb) uses Ruby's standard HTTP/JSON libraries, not an SDK. Each successful new lookup makes two authenticated HTTPS requests:

- `GET /v1/stocks/{ticker}/quote`: exact-listing price, with stale-quote checks.
- `GET /v1/screener/stocks?tickers={ticker}&limit=1`: company name. Its end-of-day price is not used.

Requests use the `Authorization: Bearer` header, five-second connection/read timeouts, and no automatic retries. Missing keys, unavailable/stale quotes, malformed responses, and HTTP failures produce an unavailable-data result without adding a portfolio entry. A `401` means the key is invalid, `403` can mean a paid plan is required, and `429` means the shared daily quota is exhausted. Check your account plan and reset time before retrying.

Official reference: [REST API](https://equibles.com/docs/api), [authentication](https://equibles.com/docs/authentication), [paid quotes](https://equibles.com/docs/api/endpoints/prices), [company screener](https://equibles.com/docs/api/endpoints/capital), and [errors and limits](https://equibles.com/docs/api/errors).

### Prepare the Database and Start Rails

```sh
ruby bin/rails db:prepare
ruby bin/rails server
```

Open <http://localhost:3000> and register an account. The default database names are `myapp_development` and `myapp_test`. [db/seeds.rb](db/seeds.rb) currently contains no sample records or preconfigured accounts.

Commands above invoke the Rails binstub through Ruby so they also work when its executable bit is missing. [bin/setup](bin/setup) provides an automated environment refresh, but its direct calls to other binstubs require those scripts to be executable.

## Usage

- **My Portfolio** (`/my_portfolio`): search for a ticker and manage tracked stocks. Quote lookup requires the paid-plan configuration above.
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

The screen is shared Rails/Hotwire UI intended for **Hotwire Native iOS and Android
apps**, not a claim that responsive web equals a native application. Native shells,
navigation, authentication/session integration, bridges, and device tests remain
separate implementation work. Real account connections and trading are not active.

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

The new tests cover paid quote mapping, Plus-plan delayed quotes, stale/invalid data, exact share-class identity, credentials, and failed portfolio additions. HTTP responses are stubbed; these checks do not validate a live subscription. Existing unrelated model/controller tests and fixtures still include generated placeholders. Minitest 6 uses the separate test-only `minitest-mock` dependency for mocks and stubs.

**Current Rails test blocker:** The locked Rails 7.1.3.4 and Minitest 6.0.6 combination raises an argument-count error in Rails' `line_filtering.rb` when running Rails test cases. The standalone Equibles client suite runs successfully under this bundle, but Rails model/controller execution needs a separately reviewed test-framework compatibility fix. A running PostgreSQL server is still required for those tests.

System tests are configured to use Chrome through Selenium, so browser-based tests require Chrome and an available compatible driver. See [test/test_helper.rb](test/test_helper.rb) and [test/application_system_test_case.rb](test/application_system_test_case.rb).

## Docker and Production

[Dockerfile](Dockerfile) builds a production image with precompiled assets and a non-root runtime user:

```sh
chmod +x bin/rails bin/docker-entrypoint
docker build -t financial-tracker .
docker run --rm -p 3000:3000 \
	-e RAILS_MASTER_KEY \
	-e DATABASE_URL \
	-e EQUIBLES_API_KEY \
	financial-tracker
```

Export `RAILS_MASTER_KEY`, `DATABASE_URL`, and `EQUIBLES_API_KEY` in your shell before running the container (the Equibles environment key can be omitted when using encrypted credentials). Ensure binstubs are executable before building. Use a PostgreSQL URL reachable **from the container**; `localhost` inside the container is not your host machine. The image does not include a PostgreSQL server, and the entrypoint runs `db:prepare` before starting Rails.

Production forces HTTPS. Deploy behind an appropriately configured TLS-terminating reverse proxy; the plain HTTP port mapping above is not a complete production deployment. Configure production mail delivery before relying on password recovery, and supply a paid Equibles key before expecting stock search to work.

Relevant runtime settings:

| Setting | Purpose |
| --- | --- |
| `RAILS_MASTER_KEY` | Decrypts Rails credentials when the key file is unavailable. |
| `DATABASE_URL` | Supplies a PostgreSQL connection URL, overriding matching database configuration values. |
| `EQUIBLES_API_KEY` | Server-side Equibles key with Plus or Pro quote access; takes precedence over Rails credentials. |
| `MYAPP_DATABASE_PASSWORD` | Password for the default production `myapp` database role when not overridden by the connection URL. |
| `RAILS_MAX_THREADS` | Database pool size and Puma thread configuration; defaults to 5. |
| `RAILS_LOG_LEVEL` | Production log level; defaults to `info`. |

See [config/environments/production.rb](config/environments/production.rb), [config/database.yml](config/database.yml), and [bin/docker-entrypoint](bin/docker-entrypoint) for deployment behavior. The build's `SECRET_KEY_BASE_DUMMY` is only for asset precompilation, not a substitute for runtime credentials.
