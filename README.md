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
architecture. The user-requested Dashboard charts are a bounded React19.3.1
island bundled with esbuild0.28.2; other pages and research chat remain Hotwire.
`tailwindcss:build` and `assets:precompile` also build that island. When binding a
macOS checkout into the Linux test container, add `-v /rails/node_modules` so
esbuild uses the image's native dependencies rather than the host binary.

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
The PostgreSQL base and Redis image are digest-pinned; the application keeps Ruby 3.3.0
and Rails 7.1.3.4. Docker Desktop with Compose v2 or newer is required.

```sh
ruby bin/compose-env
docker compose --env-file .env.docker config --quiet
docker compose --env-file .env.docker build postgres web
docker compose --env-file .env.docker up -d --wait web worker scheduler
```

Open <http://127.0.0.1:3000/portfolio_examples>. Only the web port is published,
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

### PostgreSQL vector foundation

The database image builds pgvector **0.8.1** from a SHA-256-checked release archive
on the **same PostgreSQL 16.15 base digest** in [Dockerfile.postgres](Dockerfile.postgres).
Only the extension library and SQL/control files enter the final image.
Portable compilation disables architecture-specific optimization flags.
This does not initialize a new cluster, change database users/passwords or move
data: the existing `postgres_data` volume and `/var/lib/postgresql/data` stay put.
Installing the image makes `vector` available; it does not itself enable the
extension in any database. Database migrations must enable it separately.

Before upgrading an existing local installation:

```sh
docker compose --env-file .env.docker build postgres
ruby bin/pgvector-rehearsal
# Only after the rehearsal passes:
docker compose --env-file .env.docker up -d --no-deps --wait postgres
docker compose --env-file .env.docker build web
docker compose --env-file .env.docker run --rm --no-deps prepare
docker compose --env-file .env.docker up -d --wait web worker scheduler
```

[bin/pgvector-rehearsal](bin/pgvector-rehearsal) backs up the running development
database, restores into a uniquely named, network-isolated temporary container
using memory-backed scratch storage, and checks every public table's row count
and content fingerprint, indexes and non-internal triggers. It also checks
pgvector's exact cosine join, ordinary SQL rollback and the ledger trigger's
actual rejection behavior. A second private dump/restore proves populated
1,536-dimensional vectors survive alongside the original public tables.
It never writes to the source database. Concurrent
source changes cause explicit failure; rerun during a quiet window. The helper
container is removed on success/failure, but the backup is intentionally kept.

Backups are mode 0600 under ignored `storage/backups/`; their parent is mode
0700 and the build context excludes them. They contain private application data:
do not commit, publish or attach them. Securely retain the original `.env.docker`
and encryption secrets separately; the database dump alone is not a full disaster
recovery backup of roles, secrets, Redis, uploads or an entire PostgreSQL cluster.
This local small-database rehearsal is not a production backup schedule,
encrypted offsite storage, point-in-time recovery or a measured restore SLA.

Verified 2026-11-07: the existing development database restored successfully before
the image change; PostgreSQL 16.15, the original named volume and the cluster's
system identifier survived recreation. The existing app health endpoint passed.
The installed extension files report version 0.8.1.

Rollback is conservative: stop new research writes and roll back application
code first, retaining the pgvector-capable database image, extension, research
tables and vectors. Do **not** disable/drop `vector`, cascade-drop its dependent
objects, reset the volume, or return an extension-using cluster to a base image
without its library. If an engine/image change must be reversed, test a restore
into a separate compatible image/volume before switching connections; retain the
original volume and backup. A return to a pre-vector backup is explicitly a
data-loss recovery decision for all writes since that backup, not routine rollback.

For host/managed PostgreSQL, install the same extension version through the
provider or PostgreSQL administrator, verify it in an isolated restore and keep
the existing database/roles. Extension installation/creation privileges are
environment-specific; local Compose's `rails` role is a superuser, which is not
a production least-privilege recommendation. Production availability, privileges,
backup/restore and target-platform compatibility remain deployment gates.

#### Research storage and exact vector queries

The existing relational database now also contains:

| Model/table | Stored identity and lifecycle |
| --- | --- |
| `ResearchDocument` / `research_documents` | Owner, provider/source kind/stable source ID, issuer/instrument and exact listing identity, fiscal year/period, citation URL, entitlement reference, rights deadline, revocation, current revision and ingestion generation. |
| `ResearchRevision` / `research_revisions` | Source revision ID, immutable content/checksum and temporal/source provenance, pending/ready/failed indexing state, supersession, event/publication/known-available/first-received/verified/indexed times, freshness deadline, retention expiry and revocation. Unknown source availability remains null, not invented from receipt time. |
| `ResearchPassage` / `research_passages` | Revision/owner, preprocessing and chunker versions, passage position, character/line spans, speaker, token count, immutable text/checksum and generated English full-text vector. |
| `ResearchEmbeddingSpace` / `research_embedding_spaces` | Owner, provider/model/model version, 1,536 dimensions, cosine metric, preprocessing/chunker versions and building/active/retired state. |
| `ResearchEmbedding` / `research_embeddings` | Owner, passage, space, input checksum, matching preprocessing/chunker versions and `vector(1536)`. |
| `ResearchIngestion` / `research_ingestions` | Owner-scoped idempotency key, allowlisted source selectors, stage/error, source request count, short claim lease and generation fence. No credentials or source text in the job arguments. |
| `ResearchEmbeddingAttempt` / `research_embedding_attempts` | Durable batch/generation identity, UTC budget date, reserved/actual tokens and nanodollar costs; reserved/dispatched/settled/uncertain/released outcome. |
| `ResearchRetrieval` / `research_retrievals` | Owner/space, query digest (not raw question), immutable exact selectors and idempotency key, bounded latest-event metadata, selected passage IDs/fingerprints, deadline and status. Query and ingestion attempts share one budget ledger. |

Neighbor **0.6.0** supports the locked Ruby 3.3/Rails 7.1 stack; newer 1.x requires
Rails/Active Record 7.2 or newer and is intentionally not selected.
The [migration](db/migrate/20261107060000_create_research_storage.rb) enables and
verifies pgvector 0.8.1 per database. It does not replace existing tables.
The canonical SQL schema retains both original ledger triggers and the new
embedding-space identity trigger; do not convert it to Ruby schema format.

Composite foreign keys enforce ownership all the way from document to vector,
and bind each embedding to its passage checksum and space's chunking versions.
PostgreSQL also verifies SHA-256 text checksums, passage bounds/line ranges,
token bounds, nonzero vectors and a single active space per owner. The database
vector type enforces 1,536 finite float32 values; other dimensions require an
explicit schema/index review. pgvector 0.8.1's `vector` HNSW/IVFFlat indexes allow
up to 2,000 dimensions, so 1,536 fits without half-precision conversion.

Create a new building space for any model/version/preprocessing/chunker change.
The unique `(space_id, passage_id)` key supports resuming missing work without
duplicate embeddings. `activate!` refuses empty/incomplete eligible coverage,
retires the previous active space and activates its replacement transactionally,
without deleting old rows. Space identity is immutable in both Rails and SQL.
Ordinary ORM research writes, cutover and vector reads share the owner row lock;
future bulk ingestion/disposal writers must take that same lock. Do not hold it
across network/model calls.

The M2 [schema extension](db/migrate/20261107070000_add_research_ingestion.rb)
starts every new revision as `pending`. Retrieval requires `ready`, the document's
current revision, no supersession, and valid retention/availability. Existing text
is not automatically declared indexed. The composite current-revision foreign
key also prevents pointing to another document or owner. Publication/orchestration
must be verified separately; these tables alone do not enable provider access.
The selected local tokenizer is `tiktoken_ruby` 0.0.17 (`cl100k_base`); the official
`openai` SDK is pinned to 0.120.0, with URI 0.13.3 for its parser compatibility.

`space.nearest(query_vector, limit: 5)` is an exact-cosine storage primitive,
not the complete M3 retrieval policy or an authorization API. It validates inputs,
uses only that owner's active space, and excludes revoked, currently expired or
unknown/future-available evidence. Historical availability cannot bypass current
retention/rights expiry. It follows the published current revision, but does not select the latest event, implement
full-text/hybrid ranking or authorize a provider request. Those remain separate
M3/workflow gates; no research controller, paid call or real-source ingestion
was enabled by M1. Metadata references do not themselves establish permission.
User deletion is restricted while research documents/spaces remain; reviewed
M8 disposal must handle text, vectors, derived material and backups explicitly.

Validated locally: SQL migration, Rails vector round-trip/distance order,
cross-owner/checksum/version constraints even with model validations bypassed,
invalid vectors, retention/availability boundaries, deliberate version cutover,
normal relational transactions/rollback and surviving ledger triggers.

#### M1 index decision and repeatable benchmark

[bin/research-vector-benchmark](bin/research-vector-benchmark) refuses non-test
environments/databases and creates only original synthetic evidence in a rolled
back transaction. It uses 24 documents, 120 passages, two owners, 1,536 dimensions
and 20 exact-company/period-filtered queries. Independent Ruby cosine calculations
verify exact top-five ground truth. ANN query plans are checked to ensure the
requested index was actually exercised; forced planner settings are
transaction-local. All returned IDs must satisfy the same owner/company/period
filters. Generated records and trial indexes are rolled back; the script refreshes
test-table statistics afterward.

```sh
docker compose --env-file .env.docker --profile test run --rm test \
  bash -ec 'bundle exec ruby bin/rails db:prepare && bundle exec ruby bin/research-vector-benchmark'
```

Sample standalone local result, 2026-11-07 (warm cache; SQL candidate IDs only):

| Search | Filtered recall@5 | Query p95 (ms) | Index build (ms) | Extra index bytes | Relational-query p95 with index (ms) |
| --- | --- | --- | --- | --- | --- |
| Exact cosine | 1.00 | 1.183 | none | 0 | 0.187 baseline |
| HNSW, `ef_search=40` | 0.77 | 1.438 | 37.000 | 991,232 | 0.198 |
| IVFFlat, 10 lists / 1 probe | 0.32 | 1.235 | 22.063 | 1,073,152 | 0.161 |

Stored vector payload was 737,760 bytes, excluding other columns/indexes.
**Keep exact search; no persistent HNSW/IVFFlat index is installed.** The trial
ANN settings missed filtered neighbors without making this small workload
faster. Higher search/probe settings can improve recall but need their own
measurements; this is not a general claim against ANN. Timing/index-build
variation is expected. These warm-cache, local, small-sample measurements do not
include embedding generation, Rails workflow/answer latency, concurrent ingestion,
production I/O contention or a claim that all M0/M9 acceptance targets passed.
Rerun on representative permitted growth/load before adopting an approximate
index; measure filtered recall, latency, space/build/write cost and relational
impact again rather than relying on these sample numbers.

M1 is verified locally: the full container suite passed 238 tests / 3,063
assertions with two parallel workers; eager loading and production image build
passed. The rebuilt web/worker/scheduler are healthy and sign-in remains available.
M2 ingestion and later RAG/agent/disposal work are not included. No live provider
or paid inference/embedding request was made.

#### M2 permission-aware ingestion and embedding

M2 is a Rails/Active Job backend, not a new chat UI or model-agent runtime.
[Research::Ingestor](app/services/research/ingestor.rb) enqueues only an ingestion
ID and exposes `pending/fetching/chunking/embedding/ready/failed` progress and
allowlisted error codes. Owner-scoped request keys reject changed selectors;
duplicate jobs skip completed work. `request.resume!` explicitly resumes failed
or expired-lease work, preserving fetched revisions, chunks, settled vectors and
quota usage. It refuses uncertain/dispatched embedding attempts pending operator
reconciliation; never assume a timeout was free or resend it automatically.
Uncertain batches also block a different request key for the same space/passages.

The initial source allowlist is deliberately small:

- Original `SYNTH:ALPHA`, FY2026/Q3, versions `v1/v2`, transcript/brief fixtures.
  These are fictional/public demonstrations. Their deterministic SHA-256 vectors
  test indexing/ownership only; they are **not semantic embeddings or real research**.
- Owner-private Equibles exact-period speaker transcripts and earnings briefs.
  Filings, arbitrary URLs/uploads, chats, account data and unreviewed datasets are
  rejected. There is no silent fallback from a missing transcript to a brief.

[config/research_ingestion.yml](config/research_ingestion.yml) defaults to empty
`approved_owners`; quote permissions and a populated key do not approve research.
An authorized operator must record each owner's non-secret approval reference,
exact `listings`/`source_kinds`, current offset-bearing `expires_at`,
`retention_seconds` (1..2,592,000), `freshness_seconds` (1..86,400 and no longer
than retention), and `daily_source_requests` (1..30). Every flag in
[Research::Policy::REQUIRED](app/services/research/policy.rb) must be explicitly
true: verified subscription, automated reads, text/vector storage, private
display, OpenAI processing/account access, OpenAI retention and backup retention.
`historical_storage` is opt-in, not implied. Never insert credentials into this
file. Current reported permission still lacks the M0 scope/reference/retention
details; **no real-source ingestion or paid request was enabled or executed**.
Production disposal/backup controls remain an M8 operational gate, not something
these approval flags implement.

The source adapter reads only fixed HTTPS Equibles endpoints using the owner's
encrypted `EquiblesConnection` key, not a global `.env` fallback. It validates
exact ticker/fiscal period/event ID, tombstones, available materials and page
consistency. `hasTranscript` controls access, not the nullable document ID;
partial/presentation-only/filed-summary records are rejected. At most two pages
of 50 turns are fetched; longer or inconsistent calls fail explicitly rather
than being presented as complete. Briefs use exact period filters and reject
retired/renamed listing notices. `US:TICKER` means US presentation identity, not
a verified issuer CIK/MIC; MIC-prefixed requests require exact returned identity.
API citation URLs may require provider authentication.

Each source request reserves the existing owner connection's UTC quota before
dispatch, sharing accounting with quote refreshes. The configured allowance
counts local quote/research usage conservatively, not external MCP/dashboard
clients on the same provider key. A request has at most three source calls total,
including failed/resumed attempts. Requests have no automatic retry/redirect,
a five-second total timeout and 256-KiB response cap; normalized content/provenance
also has a 256-KiB input cap. Busy connection locks fail without quota consumption.

Normalization preserves UTF-8/NFC text, speaker/role/unknown attribution,
turn/section/audio references, fiscal context, corrections and source dates.
Brief comparison objects remain literal provider JSON sections, not invented
prose. Citation lines/characters refer to the normalized representation; provider
turn indexes are retained separately. Canonical provenance and content determine
the revision fingerprint; refetch receipt time cannot extend old retention.
Empty/malformed/control-bearing content, known secrets and recognizable
credential fields are rejected before storage/egress. `cl100k_base` counts tokens
locally, including literal special-token strings; passages are at most 800 tokens,
with at most 50 overlap within the same speaker/section and valid character bounds.

The official OpenAI SDK posts only to `/v1/embeddings`, batches at most four
passages, disables retries/logging/raw-body retention and uses a five-second
timeout plus a 1-MiB streamed response cap. It supplies an explicit HTTP
idempotency header; **local receipts/fences**, not an assumed provider deduplication
guarantee, prevent replay. Count/index/model/usage and finite, nonzero, float32-safe
1,536-dimensional vectors are checked before transactional persistence. The
embedding space uses `text-embedding-3-small` as both model and declared version;
this is not a separately verified internal weights snapshot. There is no model
fallback, hosted file/vector store, inference or `store` option on this API.

Embedding attempts reserve tokens and costs before dispatch: 20,000 tokens per
owner/UTC day, $0.05/request, $0.50/owner/day and $1/application/day. Nanodollars
preserve the selected $0.02/1M-token price. Pending/uncertain dispatches retain
their reservation; known usage is reconciled even when publication is rejected.
Unexpected over-reservation usage is recorded and rejected, not hidden.
M3 query embeddings and M4/M5 inference join this accounting, including unused
durable run holds, rather than receiving an independent allowance. This is
application accounting, not verified billing, taxes or provider account caps.

Owner/document/request generations fence every phase; permission, credential
identity, revocation and expiry are rechecked before each external call and
publication. No database transaction/owner lock spans a provider/model call.
New accepted corrections immediately supersede the old current revision, so
failed indexing cannot silently serve stale text as current. Only complete
vectors publish `ready`. Historical text/vectors are retained only when permitted;
otherwise old revisions are physically removed. Deleted/expired/revoked or
previously deleted revision fingerprints are not automatically recreated.

Equibles schemas do not supply publication/known-available instants for these
sources: they stay null. Placeholder call dates are not confirmed event times.
Consequently the existing strict storage query excludes those sources until M3
defines a labelled current-research policy; M2 readiness is not point-in-time RAG,
latest-event resolution, hybrid retrieval or answer-quality acceptance.

An original offline worker exercise can be enqueued from a trusted Rails console:

```ruby
owner = User.find(owner_id)
space = owner.research_embedding_spaces.find_or_create_by!(
  provider: "synthetic", model: "fixture-1536", model_version: "sha256-v1",
  preprocessing_version: Research::Chunker::PREPROCESSING,
  chunker_version: Research::Chunker::VERSION
)
request = Research::Ingestor.enqueue!(
  user: owner, space: space, request_key: "original-alpha-2026-q3",
  provider: "synthetic", source_kind: "earnings_transcript",
  listing_identity: "SYNTH:ALPHA", fiscal_year: 2026, fiscal_quarter: 3,
  fixture_version: "v1"
)
# After the worker completes:
request.reload
raise "Index not ready: #{request.error_code || request.state}" unless request.state == "ready"
space.activate! if space.reload.state == "building"
```

Real embeddings additionally require a server-managed `OPENAI_API_KEY`; Compose
accepts it optionally from the ignored `.env.docker` without auto-copying `.env`.
Do not configure it or authorize private material merely to run these fixtures.
Offline tests exercise the real SDK with original fake HTTP replies, source
pagination/limits, exact token thresholds, resume/dedup, quota/spend contention,
corrections, revocation/deletion/expiry during calls and SQL ownership constraints.

Local M2 validation, 2026-11-07: **269 tests / 3,352 assertions** passed with
two workers; production image/assets and running-image eager loading passed.
Isolated restore verified every public table/index, original ledger triggers
and populated 1,536-dimensional vectors. The actual Sidekiq worker persisted an
original fixture, two vectors and valid exact retrieval with zero external
calls/spend; its temporary owner/corpus/receipts were then removed. The stricter
benchmark returned exact recall@5 1.00/p95 1.731 ms with no persistent ANN index.
Web/worker/scheduler and sign-in are healthy. This verifies local implementation,
not live provider acceptance or complete RAG/agent behavior.

#### M3 temporal and hybrid retrieval

`Research::Retriever` implements Rails-owned retrieval/context preparation, not
a chatbot or inference/agent runtime. It uses the same owner-scoped M2 corpus,
permissions and budget ledger; private access still defaults off.

- **Time/provenance:** eight UTC clocks distinguish event, publication,
  knowability, first receipt, last source verification, indexing, relevance
  recheck and deletion. Original offsets and raw date-only/placeholder values
  survive; missing instants stay null. Immutable timestamp basis/confidence and
  ingested UTC proof prevent a changed timestamp from proving historical access.
  Legacy rows are not backfilled with invented provenance.
- **Reverification, not renewal:** a successful unchanged-source fetch updates
  verification/freshness only, never first receipt, knowability or deletion.
  Replaying an already-ready ingestion performs no fetch and cannot refresh it.
- **Modes:** `current` accepts labelled unknown publication/knowability, not
  future-dated evidence. `as_of` requires historical permission and a confirmed,
  revision-specific known-time proof at/before the explicit offset-bearing
  cutoff. It selects the then-known version even if downloaded/indexed later.
  Unknown or tied restatement histories conservatively block the document;
  failed/newer versions cannot cause an older revision to masquerade as valid.
- **Relevance vs retention:** current earnings need a fresh source recheck;
  latest earnings need freshly resolved authoritative metadata (at most 15
  minutes, capped by owner policy). Filings are not aged out solely by event
  age. Quote rules use observation age (120 seconds), and company-fact rules
  have no blanket age cutoff; these two rules do not add ingestion connectors
  or expand the currently allowed corpus. Hard rights/revocation/retention
  always apply, including shortened current policy limits. Stale text remains
  distinct from text that must be deleted; physical disposal/backups remain M8.
- **Database eligibility first:** owner, active/versioned hybrid space, exact
  provider/listing/presentation-instrument, fiscal period, source kind,
  approval reference, current rights, lifecycle and temporal mode are filtered
  before ranking. M1 `nearest` stays a strict storage primitive, not this
  application query interface. Complete indexing can activate a space even
  when publication history is unknown.
- **Keyword baseline and optional hybrid:** generated English `tsvector`/GIN,
  `websearch_to_tsquery` and `ts_rank_cd` supply keyword ranking. Explicit
  `strategy: "hybrid"` adds exact cosine candidates with distance <=0.5
  (similarity >=0.5), fused with reciprocal ranks `1/(60 + rank)` per channel.
  Each channel is capped at 100 candidates; equal checksums are deduplicated.
  Optional recency breaks fused-score ties using known dates, not receipt.
  Materialized eligible rows/distances prevent a future ANN index from
  truncating this exact baseline. Queries have a five-second SQL timeout,
  restored transaction-local settings, and deterministic ID tie breaks.
  **Keyword is the default:** M0's required hybrid quality gain is not proven
  by fixture tests or ANN timings; adoption/evaluation remains M9.
- **Latest earnings:** resolve the fixed REST investor-event listing first,
  including uncaptured/tombstoned events, then verify the exact event/period.
  A bounded 50-event window, future events, ordering/count/identity failures,
  placeholders, unknown dates or missing material produce explicit absence or
  errors. Select only a matching latest-event brief, otherwise its complete
  exact-period transcript. Never use an older brief or derive "latest" from
  the ingested corpus. At most two metadata requests share the existing owner
  quote-account quota; no app-wide provider-key quota guarantee is implied.
- **Bounds/accounting:** queries <=500 cl100k tokens, <=2,000 characters and
  <=4,096 bytes; context <=6 passages, <=6,000 actual serialized JSON tokens
  (default 4,000), <=64 KiB, request deadline 90 seconds. Context includes IDs,
  citation spans/URLs, dates, fiscal period and uncertainty. `no_evidence` and
  `stale_only` never synthesize a replacement source. Query embeddings use the
  official bounded SDK and the same daily/global/owner M2 reservations, with
  cross-request uncertainty blocking and known usage reconciliation.
  Durable requests retain digests/selectors/IDs, not raw questions or query
  vectors. Idempotent completed requests recheck the original selection;
  changed/expired evidence requires a new request, not an implicit paid retry.
- **Dispatch/publication:** `EvidenceSet#dispatch!` rechecks live permissions,
  source credentials, selected fingerprints/current revision, expiry and space
  just before yielding model context outside database transactions. It locks
  selected passage/revision/document rows and rechecks before invoking the
  local transactional publisher. Revoked/expired/changed evidence prevents
  publication; already-transmitted data cannot be recalled. The model block
  and local-only publisher are used by the M4 native loop below. M3 itself
  supplies no inference adapter, conversation store or streaming UI.

Example with an already ingested, owned original-fixture space:

```ruby
result = Research::Retriever.new(
  user: current_user, space: space, request_key: SecureRandom.uuid,
  query: "How did revenue change?", listing_identity: "SYNTH:ALPHA",
  mode: "latest_earnings" # Keyword baseline; add strategy: "hybrid" explicitly to evaluate it.
).call

if result.status == "ready"
  context = result.context_json # Revalidates; no provider call.
else
  [result.status, result.reason] # Explicit no-evidence/stale-only outcome.
end
```

For exact questions pass `fiscal_year: 2026, fiscal_period: "Q3"`. Historical
questions additionally use `mode: "as_of", as_of: "2026-11-01T00:00:00Z"`.
Synthetic vectors are demonstrative hashes, not semantic financial research.
No real provider/paid request, permission enablement or M0/M9 end-to-end
quality/budget/latency acceptance follows from this implementation.

Local validation (2026-11-07): **301 tests / 3,547 assertions**, plus knowledge
**28 / 266**, passed. Production image/assets, running-image eager loading,
healthy web/worker/scheduler/sign-in and a real Sidekiq v1/v2 original-fixture
latest/as-of/hybrid-receipt/guarded-publication smoke passed. The fixture made
zero external calls/spend and was removed completely. Pre/post-schema isolated
restore preserved public rows/indexes/ledger triggers and populated vectors
without changing the source PostgreSQL volume. Adversarial tests and EXPLAIN
show the exact eligible baseline is not truncated by the trial HNSW index.

## Local Setup (Without Containers)

Run the following commands from the repository root.

### Prerequisites

Install Ruby 3.3.0, PostgreSQL 16 with pgvector 0.8.1 available, a JavaScript runtime such as Node.js for ExecJS/asset compilation, and native build tools for gems such as `pg` and `sassc`. PostgreSQL development headers and `pg_config` must be available when compiling `pg`.
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

#### C01 real-data stocks and earnings dashboard

`/dashboard` is the authenticated default sign-in destination and root redirect.
An explicit stored destination still wins. `/market_dashboard` aliases it;
the old `/portfolio_demo` redirects there, while public fictional scenarios now
live at `/portfolio_examples`. Provider display remains **local and gated**.
An authenticated GET requests fresh data server-side, including without JavaScript.
The ten US listings are
ranked by Equibles market capitalization (`market=US`, `sortBy=marketcap`,
`sortAscending=false`, `limit=10`). Share classes remain separate listings;
this is the provider-covered universe, not ten distinct companies. Initial loading
uses eight exchanges: screener, one `/v1/quotes` batch, five daily histories and
selected-stock diluted EPS; a selection outside the first five adds one history.
Five independently colored React charts use `useState`, `useReducer`, `useMemo`,
`useRef` and cleaned-up `useEffect` subscriptions. Range controls and keyboard/
pointer cursors are independent. Server-rendered charts remain the no-JS fallback.
React roots unmount on navigation and board replacement. A chart-led layout has a selected-stock panel,
market-leader list, dated OHLC metrics and reported earnings. No Google artwork,
invented figures, OpenAI calls, trading or screener-price substitution is used.

Quotes refresh every900,000ms (15 minutes) **while visible**, using one batch call
for all ten listings. Hiding the page pauses the timer; a due refresh runs on
return. Requests never overlap within the widget. Provider/auth/quota/network
errors pause automatic work and explicitly mark previous figures as not current.
Refreshes do not run in background jobs. Rankings are reloaded on UTC-day rollover
or manual refresh; the current selected listing is preserved when still ranked.
Stock selection fetches a quote, bounded daily history and quarterly EPS; changing
chart ranges is local and consumes no requests. Non-JavaScript load/selection
forms remain usable, without claiming automatic updates.
Disconnecting aborts browser delivery, not already accepted provider work; those
requests may still complete and remain counted.

Enable locally with `MARKET_DASHBOARD_ENABLED=1`; the flag defaults off and cannot
enable this surface in production. The host must be loopback/approved development
emulator and pass existing private-transport checks. Docker receives
`EQUIBLES_API_KEY` **only in web**, not as an image/build argument or in worker job
payloads. The local operator can let Docker load existing environment files
without opening or displaying their contents:

```sh
MARKET_DASHBOARD_ENABLED=1 docker compose --env-file .env --env-file .env.docker \
  up -d --build --wait web
```

The environment files remain protected/ignored. Never print interpolated Compose
configuration, credentials or raw provider responses. Removing the key or
disabling the flag stops further dashboard access; a key's presence does not
authorize AI requests, caching or hosted redistribution.

When the flag is disabled, Dashboard is still an authenticated200 page with an
operator notice; paid refresh is denied. The reviewed OpenAPI has no verified
renewal notification/webhook/stream endpoint. Visible15-minute snapshot checks
cannot promise synchronization with every provider renewal. Identical source
timestamps are not reported as newly published readings.

**Persistence is UI metadata only.** An authenticated, CSRF-protected
`GET`/`PUT /dashboard/preferences` validates a versioned selected ticker and at
most ten chart ranges. Redis keys are environment/owner scoped and stable across
web rebuilds; browser keys use an opaque owner HMAC. Redis expires preferences
after24 hours. localStorage keeps only a dated preference envelope; expired
envelopes are rejected/deleted on the next read, not promised physically erased
while an unused browser remains closed. Local preferences restore ranges first,
otherwise Redis restores them; Redis restores selected listings for the next
fresh server request. UI preference writes are last-writer-wins, not a financial
ledger. No quote/history/EPS/profile text, credentials or private account payload
is persisted in either store. Storage and Redis failures are visible, not
success-shaped backups. Redis AOF (`appendfsync everysec`) and its persistent
Compose volume provide crash persistence, **not a tested independent/offsite
backup or zero-loss guarantee**. Licensed snapshot caching remains blocked
pending confirmed rights.

Quotes retain exact ticker/USD identity, provider market/session time and receipt
time. Delayed quotes are supported and labelled; stale, malformed, wrong-currency
or future-source-time quotes are unavailable, not relabelled live. Diluted EPS
shows at most four captured discrete quarters with period end, filed date, unit
and split basis for the selected stock. Negative/zero EPS remain real values;
missing earnings are not zero. Source dates stay date-only. Latest-restated XBRL facts and today's split
basis are not point-in-time/backtest evidence, forecasts or an earnings-call
summary. Stock selection is not a holdings ledger. Fifteen-minute delayed SIP
means source lag, not a guarantee of a new provider reading every15 minutes.
Charts use up to300 daily bars within366 calendar days, not historical intraday
candles. Ranges show up to5/22/132/all captured sessions (5D/1M/6M/1Y), with
actual first/last dates. Historical changes and OHLC are dated daily-session
figures, not today's intraday changes; unavailable history draws no fake line.

Prices, financial facts and profile text remain in the response, not SQL,
embeddings, sessions or a shared watchlist. Pages use no-store and no Turbo
cache. Only quota receipts with irreversible key digest and UTC date/count are
stored through existing `ResearchSourceUsage`. Each exchange reserves capacity
atomically before networking and shares key-group accounting with REST/MCP and
queued research holds. The previous30-request ceiling is now120 requests/key/UTC
day, a bounded implementation assumption for the requested automatic dashboard.
A continuously visible tab needs roughly96 quote batches/day plus initial/detail
work. Extra tabs, reloads or selections can exhaust this allowance; there is no
shared retained market-data cache to silently deduplicate them. Remote clients can
consume additional allowance. Observed exhaustion/auth failures stop later calls;
accepted errors/timeouts keep reservations and there are no retries. A 20-second
admission deadline stops starting further exchanges; an already accepted request
may finish afterward. Database locks do not cover network work.

The 2026-11-07 quote-only polling/selection checks remain verified. The expanded
2026-11-08 dashboard rendered ten listings and five distinct colored React charts;
independent5D/6M ranges, keyboard cursor inspection, metadata-only localStorage
and matching authenticated Redis state were verified in the local browser.
Clearing the browser copy recovered ranges and selection from Redis on reload.
Original synthetic UI checks verified browser-only restoration, blocked-storage
warnings, quote updates surviving range changes and root cleanup on unmount.
The embedded browser was backgrounded, so this is DOM acceptance, not physical/
native-device proof.
No actual prices, earnings figures, keys or real-data screenshots are retained
in shared acceptance records.

Run UI regression tests with `npm run test:ui`; Rails preference tests cover
authentication, owner isolation, expiry, invalid/licensed payload rejection,
CSRF and explicit Redis failures. Production and development builds include
the locked React bundle.
Final validation:408 Rails tests/4,595 assertions,36 knowledge tests/563
assertions and25 UI tests passed, plus development/production image builds.

This completes the requested local real-data dashboard, **not** C01's still
unverified exact named account plan/expiry, C03 caching/redistribution permissions,
public hosting/screenshots/mobile distribution or any commercial launch.

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

#### Free/Plus educational research scope

The next evaluation stage uses Free/Plus resources first; Pro is not a
prerequisite for learning or source-linked company research. These are research
inputs, not evidence that a profitable strategy exists or that the app currently
implements one.

- Free provides filings, financial/ownership research and historical/end-of-day
  prices; API/MCP daily prices are released four hours after the market close,
  with 100 shared requests per day.
- Plus adds 15-minute-delayed US quotes, delayed/indicative option-chain data,
  10,000 shared API/MCP requests per day and 100 ALVIS credits per week. Some
  forecasts are available, but are not necessarily forecasts of a stock's return
  and do not establish an execution edge.
- ALVIS is usable on Equibles' own site. Its official documentation charges one
  credit per message/follow-up and three per workflow, subject to both weekly
  and rolling five-hour limits. Deep Thinking requires Pro. There is still no
  verified public ALVIS inference API for this Rails application. That is not
  a blocker for research: REST serves data and provider-generated earnings briefs
  and insight scores, while MCP supports research with a connected assistant.
  A separate model is optional for additional synthesis, not required merely to
  display documented research outputs; its costs/permissions would be separate.
- These resources can support end-of-day research and slower hypotheses. Delayed
  quotes are not live order prices and do not support claims of reliable
  intraday execution. No historical intraday candle/streaming service, complete
  point-in-time backtest dataset or automated profitable strategy is established.
- The existing sandbox uses fictional synchronous fills. It is not a live-data
  paper brokerage, a validated backtester, or a functioning stock-order adapter.
  Learning can begin with provider-site research and a manual paper journal;
  app-based retained research and real execution retain their separate gates.
- Evaluate a written hypothesis, invalidation/risk conditions, timestamped
  evidence, realistic fills, spread/fees, subscription costs, drawdown and an
  appropriate benchmark. A single winning trade does not establish skill or
  justify scaling risk. No return or time to profit is guaranteed.

The official [screen-and-deep-dive recipe](https://equibles.com/docs/recipes/screen-and-deep-dive)
provides a concrete starting workflow: screening, ownership/insider evidence,
fundamentals/valuation and an earnings brief. The
[REST/MCP comparison](https://equibles.com/docs/mcp-vs-rest) recommends REST for
backends/dashboards and MCP for conversational exploration; they may be combined
but have overlapping, not identical coverage. The
[earnings reference](https://equibles.com/docs/api/endpoints/earnings) documents
provider-generated briefs and insight scores, distinct from invoking ALVIS.
These research surfaces are documented capabilities, not yet credential-tested
in the eight-request quote/history exercise. Validate each selected endpoint's
plan access, provenance and availability rather than treating missing ALVIS
inference access as a general lack of usable insights.

For support, distinguish plan access from usage permission. Request confirmation
of Plus personal automated/non-display research and backtesting, permitted local
caching and backup retention/deletion, external-model inference versus training,
ALVIS programmatic access and five-hour limits, point-in-time history/delistings/
adjustment revisions, and any separate grants for public screenshots, native
delivery or redistribution. Do not describe an unverified feature as absent or
an unresolved permission as an outright ban.

Sources: [current pricing](https://equibles.com/pricing),
[ALVIS usage and limits](https://equibles.com/docs/alvis),
[price timing and adjustments](https://equibles.com/docs/api/endpoints/prices),
and [terms](https://equibles.com/legal/terms), reviewed 2026-11-07.

### M4 model and MCP adapter foundation

The backend now uses the existing official **openai 0.120.0** SDK and pinned
**mcp 1.9.0**, **faraday 2.15.1**, and **event_stream_parser 1.0.0**, compatible
with the unchanged Ruby 3.3/Rails 7.1 application. OpenAI Responses requests use
`gpt-5.4-mini-2026-03-17`, low reasoning, `store: false`, encrypted reasoning
continuation, no background execution, parallel tool execution or automatic
retry/failover. Usage includes billable reasoning output; cached-input discounts
are not assumed. Final typed SDK responses are recursively serialized through
the SDK's JSON API, not its shallow `to_h`.

Equibles MCP uses only `https://mcp.equibles.com/mcp`, encrypted owner credentials
in the Authorization header, an explicit 2025-11-25 handshake and negotiated
session headers. No query-string authentication, OAuth/browser flow, stdio,
sampling, roots, elicitation, autonomous URLs or write tools are exposed.
JSON and SSE decoding, session lifecycle and cancellation belong to the MCP SDK.
The small Faraday adapter delegates sockets to the existing OpenAI SDK's
deadline-aware Net::HTTP implementation: it recalibrates socket timeouts across
headers/body chunks without introducing asynchronous Ruby timeout exceptions.
The fixed-endpoint guard runs before requests; responses have a 256-KiB total
cap, requests a five-second remaining-time cap, and resumption GETs are denied.
The pinned SDK's internal fused-enumerator close helper releases aborted bodies.
No HTTP transport or SSE parser is reimplemented.

Discovery is bounded to two pages of at most 200 tools each. Only
`GetEarningsCallEvent`, `GetEarningsBrief`, and `GetEarningsCallTranscript` are
reviewed. Server descriptions never become system instructions. Flat server
schemas are checked, remote references rejected, and each call also satisfies a
strict application schema fixing ticker/year/quarter, brief limit 1 and transcript
limit 50/offset 0 or 50. Changed schemas, expired sessions, unsupported content
and provider errors abort rather than silently retry. Rendered financial identity,
date and transcript-range headers are validated against the documented format;
date-only UTC sessions remain dates, with publication/knowability explicitly
unknown. Format or identity changes fail closed instead of inventing metadata.

Owner-bound run/model receipts contain digests, selectors, pinned model/prompt,
usage, budgets and error codes, not raw questions, prompts, tool results or
answers. PostgreSQL ownership and immutable run/credential/association guards
protect audit identity. Inference and embedding reservations share the existing
owner/application UTC spend ceilings and global lock; all callers acquire owner
then global locks consistently. Known usage is reconciled; dispatched/uncertain
model usage blocks further owner calls pending review. M5 adds owned conversations
and durable workers below; browser/reconnect control, physical deletion and live
production acceptance remain separate. Live authorization remains default off.

Sources: [official OpenAI Ruby SDK](https://github.com/openai/openai-ruby),
[MCP Ruby transports](https://ruby.sdk.modelcontextprotocol.io/client/transports/),
[MCP cancellation](https://ruby.sdk.modelcontextprotocol.io/client/cancellation/),
[Equibles MCP](https://equibles.com/mcp), and
[earnings tool contracts](https://equibles.com/docs/mcp/tools/earnings).

### M4 application-owned native loop

`Research::Agent::Runtime` is a synchronous server-side service, not a browser
chat endpoint or background agent job. The safe default runs original fixtures
without OpenAI, Equibles or embedding requests:

```ruby
result = Research::Agent::Runtime.new(
  user: owner, request_key: SecureRandom.uuid,
  query: "Summarize original fictional Alpha earnings.",
  listing_identity: "SYNTH:ALPHA", fiscal_year: 2026, fiscal_quarter: 3
).call
```

The result has `run_id`, `status`, `text`, attributed `sources` and per-step
`usage`. The owner-bound receipt retains audit metadata, not the raw answer.
Modes must be explicit: `fixture`, `retained` (M3 `evidence:` only, no MCP
discovery), `live_mcp` (no implicit retained passages), or `mixed` (both).
Retained/mixed require an owned M3 EvidenceSet matching the exact listing,
period and mode. `query_mode: "as_of"` requires retained evidence and its
confirmed cutoff. `latest_earnings` requires guarded M3 authoritative event
metadata even if local passages are absent; MCP event identity must match it.
Missing/stale-only retained evidence returns `no_evidence`/`stale_only` without
calling a model. Live MCP publication/knowability is unknown, not as-of proof.

Each step checks approval, credentials, cancellation, deadline and selected
evidence; validates allowlisted calls; reserves usage before network work;
normalizes evidence; then continues. Repeated name/arguments reuse evidence,
not another request. Tool text/descriptions/documents are untrusted data, not
authority to change instructions, tools, scope or budgets. Sources keep
`retained`/`live_mcp`/`fixture` origins and synthetic markers; injected SDK clients
are test fixtures, not evidence of live provider acceptance.

Admission is one active run/owner, two application-wide. Limits are four model
steps, six data calls including linked latest-event requests, 90 seconds,
10,000 reserved input tokens/step, 12,000 cumulative input and 4096 cumulative
output including reasoning. No tools execute after the fourth step. Source
context is at most six sources, 6000 JSON tokens and 64 KiB; serialized model
history/tools must remain within 9000 tokens before a 1000-token framing
allowance. Token reservations are conservative estimates, not a guarantee of
provider billing. Spend is shared with embeddings: $0.05/run, $0.50/owner UTC
day and $1/application UTC day. MCP control/data exchanges share the existing
quote quota, with at most 16 exchanges/run and the verified allocation capped
at 30/owner/day. Unknown dispatched model usage blocks new paid reservations;
request keys cannot silently replay or switch providers.

Validated answer text must contain an available source ID; this is **citation
presence, not complete claim-entailment or financial-correctness verification**.
M9 quality acceptance remains required. Final local publication rechecks and
locks selected retained evidence, owner/run and credentials. Revocation,
correction, expiry or stale live observations prevent publication; known usage
still settles. Already-transmitted evidence cannot be recalled.

`events:` accepts an internal callback with version 1, run ID, sequence,
UTC time, lifecycle/tool progress, safe errors and text deltas. Financial text
deltas are buffered until full-output validation and guarded publication; tool
progress contains no raw results or credentials. Expected local persistence/
delivery errors surface explicitly; delivery failure after committed publication
does not relabel the run unpublished. These are **not AG-UI events**, authenticated
browser streaming or reconnect guarantees. Keep publishers local-only and
transactional; caller-supplied adapters are trusted application/test code.

Private research additionally requires `agent_enabled`, `derived_answers`,
the pinned `inference_models`, and all existing verified research permissions.
MCP modes also require `mcp_enabled` and an explicit reviewed `mcp_tools` subset.
Populated environment keys alone authorize nothing. M5 below adds conversation/
follow-up budgets and durable worker recovery. Workflow controls, owner-
authenticated cross-process chat/reconnect, disposal and live/quality acceptance
remain M6-M9. No real model/MCP account call or private approval was performed.

### M5 durable research lifecycle

The durable backend wraps M4 without adding a browser chat page. Submit an owned
original-fixture run with `Research::Agent::Lifecycle.submit!`, supplying the
same query/request key/listing/fiscal selectors as M4. It returns a queued
`ResearchAgentRun` with an owned conversation, encrypted user message, immutable
workflow/prompt/pricing versions and lowering-only `preferences` (string keys).
Pass the conversation on follow-ups; the scope cannot change, at most four
submissions are allowed, and preferences cannot raise its original limits.
Owner-scoped reads use `Lifecycle.messages!(user:, conversation_id:)`.

`ResearchAgentJob` receives only the run ID on the dedicated `research` queue.
The separate `research_worker` has two threads; the maintenance worker does not
consume research jobs. PostgreSQL admission still enforces one active run/owner
and two application-wide, including synchronous M4 runs. Atomic claims establish
a random 20-second lease, renewed at guarded checkpoints without extending the
original submission-to-completion deadline. Duplicate deliveries cannot claim a
running or terminal run. Only pre-claim capacity contention may requeue at
15-second intervals, at most four total enqueue attempts and never beyond the
deadline. Provider/model/MCP requests have no automatic charged retry.

Chat has separate retention: original fixtures expire after 24 hours; private
research requires explicit `chat_retention_seconds` of 1..86400, bounded by
licensed retention and approval expiry. Financial answers may expire earlier
with selected live evidence. Bodies are encrypted and filtered from model
inspection/logs; messages do not duplicate raw tool results. Read guards recheck
current approval/credentials, selected retained revisions and expiry. A
display-only evidence restoration never grants another model dispatch or extends
the original retrieval/run deadline. Completed conversation history is bounded
by the same model context caps and rechecked across steps.

Queued paid runs reserve their run ceiling against conversation ($0.20),
owner UTC-day ($0.50) and app UTC-day ($1) spend before queue delivery. Model and
embedding receipts share these holds, not new allowances. Terminal runs release
unused capacity while dispatched/uncertain usage remains reserved for explicit
reconciliation. Pricing is pinned per run; a changed rate card or UTC budget
window stops execution instead of repricing/replaying accepted work.

MCP/REST/quote quota shares one-way owner-key groups and atomic reservations.
Queued live runs hold bounded protocol capacity; other REST and quote calls
cannot consume it. Monotone per-key UTC-day usage survives credential rotation
and connection/owner deletion; owner references are nulled, not provider usage.
Rotation conservatively carries the existing counter onto the new key too until
UTC reset. Key grouping does not establish which distinct keys share a remote
billing account. Quote network reads occur outside database locks, then
recheck credentials/approval before saving; late old responses/errors cannot
overwrite a newer credential's snapshot. Private live agents additionally
require reviewed `quota_daily_capacity` (<=30), `external_usage_reserved_requests`
and `quota_reviewed_until` (future, <=24 hours). Missing/stale/unprepared key
groups are `source_budget_unknown`, not an assumed unused account.
`rails research:prepare_quota_keys` computes private one-way groups locally;
it makes no provider call.

Response observations retain only bounded quota metadata, not arbitrary
headers/credentials. `x-ratelimit-remaining`/`ratelimit-remaining` constrain
capacity only with explicitly reviewed
`quota_header_semantics: utc_daily_requests_remaining`; this does **not** claim
Equibles currently supplies those headers or that their units are verified.
Unknown units stop the live agent. Observations never raise an allowance;
429 blocks the UTC window and numeric Retry-After is diagnostic only. Remote
usage beyond the reviewed allocation is unobservable: local caps are not
guaranteed provider billing/account limits.

`Lifecycle.stop!(user:, run_id:)` cancels queued work or records a stop flag
checked during model streaming, MCP body reads and between steps. Unsafe partial
financial text is not published: incomplete answers retain metadata/known usage
or conservative uncertain reservations, not unvalidated text. Accepted work may
still be billed; cancellation is not a refund.

Expired queues fail explicitly; expired leases become `interrupted`, never an
automatic whole-run replay. Recovery runs on research-worker startup, before
claims, and every maintenance scheduler tick (300 seconds); operators can run
`rails research:recover`. It also nulls expired chat bodies while retaining
audit/usage rows. This is not physical erasure from backups or provider logs;
M8 remains necessary. Redis enqueue ambiguity leaves a durable queued record and
safe request-key lookup, with explicit queue failure rather than a success
fallback. M0 private permissions/account gates remain default off; M6-M9
workflow/UI/reconnect/disposal/live and quality acceptance remain separate.

Local M5 verification: 346 Rails tests/4,007 assertions and 31 knowledge
tests/406 assertions passed. Development/production builds, eager loading,
healthy isolated research/maintenance workers, actual queued original-fixture
completion (encrypted messages/receipts, zero external calls or cost), and full
schema/data/index/trigger/populated-vector restore passed without replacing
the original database volume.

### M9 offline acceptance and gated rollout

`RAILS_ENV=test bundle exec rails research:evaluate` runs
`original-earnings-acceptance-v1` only in the test database, outside an open
transaction. It creates and removes 24 original documents (four fictional
companies × three fiscal periods × transcript/brief), 120 passages and two
owners. Forty fixed questions comprise 20 supported, ten missing/out-of-scope
and ten temporal/adversarial cases. Separate tests cover corrections,
revocation, disposal/embedding races, malformed streams, injection, accounting,
interruption and cancellation. No live credentials, copied transcripts,
provider calls or charges are required.
Development execution and open transactions are explicitly rejected without
creating corpus. Disabling both retrieval channels raises rather than returning
success-shaped empty evidence.

The evaluator injects a **test-only** original-company permission scope through
the existing policy factory; production fixtures remain restricted to
`SYNTH:ALPHA`, FY2026/Q3. Independent golden owner/period/type/availability IDs
check ranked results, rather than treating the retrieval filter itself as truth.
The corpus fingerprint includes scope, ownership class, source type, availability,
expiry and content:
`45a287e768c35d8a02fbb7cc53337e67a7309ba6d0dc03b76a027f8c8ab3b652`.

Measured locally on 2026-11-07 with Ruby 3.3.0, Rails 7.1.3.4, PostgreSQL 16.15,
pgvector 0.8.1, OpenAI Ruby 0.120.0 and MCP Ruby 1.9.0:

| Baseline | Recall@5 (20 supported) | Retrieval p95 | Extractive fixture support | Unsupported-number probes rejected |
| --- | --- | --- | --- | --- |
| Keyword | 90% (18/20) | 53.908 ms | 100% | 18/18 |
| Vector | 0% | 41.805 ms | Not measurable: no claims | 0 attempted |
| Hybrid | 90% (18/20) | 48.676 ms | 100% | 18/18 |

All three returned zero evidence for the 20 negative cases and zero golden
ownership/temporal/scope leaks. SHA256 fixture embeddings are deliberately not a
semantic model; vector failure and two synonym misses are reported, not hidden
with unrelated evidence. Hybrid gain is zero, below the five-point adoption
threshold: keyword and exact eligible vector search remain the defaults, with
no persistent approximate index.

A temporary actual HNSW plan with `ef_search=40` recovered only **44%** of exact
filtered candidates with iterative scanning off. The same plan with
`hnsw.iterative_scan=strict_order` recovered **100%**, without eligibility leaks.
This candidate-only experiment has no relevance cutoff and is not ANN rollout
approval. It demonstrates why unfiltered nearest neighbours plus post-filtering
can lose valid evidence. Both configurations and the index-use proof are recorded;
the index is removed even on evaluation failure.

Twenty independently persisted original-fixture earnings workflows measured
314.577 ms first/cold execution, 188.923 ms warm p95 and 188.923 ms overall p95,
below the 2-second offline contract. Known zero-cost usage is settled; workflow
records and evaluation owners are cleaned afterward. These are in-process fixture
measurements, not remote inference, queue-inclusive p95 or human-reviewed financial
entailment. Extractive support does not establish real-world accuracy.

The actual rebuilt Compose web/dedicated research worker completed a zero-cost
fixture with three model steps, two tools, two saved messages and lowering-only
1500-output-token/three-tool/60-second controls. Authenticated Redis/Cable
connection and canonical Turbo recovery were checked with **simulated foreground
visibility** in the embedded browser; an unsent draft was preserved and no second
run appeared. Background visibility intentionally suppresses snapshot refresh.
This is not physical-screen or iOS/Android acceptance.

Final Rails regression: **382 tests / 4,401 assertions**, plus **35 curated
knowledge tests / 539 assertions** and successful eager loading.
Development/production asset builds, existing Rails regressions, 20 native route
cases, four Swift URL-policy tests and isolated complete-fingerprint database
restore/SQL rollback passed. Feature disablement returns authenticated 404 without
deleting saved research records; reenablement uses the same database volume.
Disable chat first for rollback; never drop relational tables or use
`DROP EXTENSION ... CASCADE`. Restored traffic remains subject to M8 quarantine.

**Not production-ready:** M9-08 paid/live checks require separately recorded
rights, account/model and budgets; at least 20 authorized live runs and human
claim review remain unperformed. M6-06 physical iOS/Android session, keyboard and
background acceptance, operational encrypted/PITR/offsite backup retention,
provider erasure and production-load acceptance remain open. Defaults still
disable chat and private/paid inference; an explicitly enabled fixture page grants
none of those permissions and no trading capability.

### M8 expiry, dependency invalidation and restore quarantine

Research maintenance is separate from quote-snapshot approval. Every 300 seconds
the scheduler enqueues an argument-free `ResearchDisposalJob` on maintenance;
failed enqueue cannot refresh its heartbeat. `bundle exec rails research:dispose`
runs the same idempotent sweep. Database owner locks fence ingestion, retrieval
and publication; no network work is performed under disposal locks.

Read-time owner/permission/revision/expiry guards remain authoritative before
cleanup. Source-derived **questions and answers** recheck the owned retrieval
dependency, including legacy metadata without passage IDs; untracked local
sources fail closed. Retrieval selections and bounded canonical source IDs
link sources to derived messages. Deletion clears selections, redacts both
halves of affected runs, cancels active work, deletes embeddings before passages
and revisions, and clears restrictive current-revision references. Document
tombstones/generations and retained ingestion fingerprints fence late jobs and
re-fetch of deleted material. Existing superseded-purge paths use this same
dependency-aware deletion. Permitted historical versions and stale-but-useful
filings are not deleted merely for age/relevance.

Connection removal purges private corpus/chat bodies but not independent
fixtures. Explicit owner deletion is available through `research:purge_owner`
with `RESEARCH_OWNER_ID` and `CONFIRM_PURGE_RESEARCH=YES`. Tombstones/audit
receipts remain; this is not complete account/ledger erasure. Undispatched
reservations release; accepted unknown usage remains uncertain, never refunded.
Malformed policy/infrastructure uncertainty raises rather than silently
destroying corpus. Sweeps log counts and maximum *known* deadline-to-cleanup
lag; withdrawals without a recorded deadline are counted as unknown. The
300-second interval plus queue delay is not a verified maximum cleanup SLA.

Before restoring a database, isolate it and set `RESEARCH_RESTORE_PENDING=1`
on **all** web/worker/scheduler processes. Application pages return 503,
Cable rejects access and research dispatch is denied. Run
`bundle exec rails research:restore_review`: copied active runs/ingestions/query
work are interrupted without replay; disallowed corpus and copied chat bodies
are purged while permitted historical corpus can remain. The gate stays on.
Review backup rights, restored quota/billing uncertainty and purge output before
restarting with `0`; do not reuse saved jobs as authorization to pay again.
Malformed gate values fail closed. Process liveness is not restore clearance.

Pure original-fixture backups have the M0 ceiling of seven days. Private research
additionally requires explicit `backup_retention_seconds` (1..604800, no longer
than source retention), `backup_controls_verified=true` and existing backup
rights approval in the separate research policy. These are operator attestations,
not automatic proof of encrypted snapshots, offsite retention or provider erasure.
The local rehearsal's protected full-database dumps contain application data:
they are **not** classified as pure-fixture backups, encrypted/PITR/offsite backup
acceptance or automatic disposal. Their retention remains an operator-review
gate; do not delete unrelated backup files based on research-only approval.
Logical deletion and removal from SQL/vector/full-text search are verified
locally. Vacuum/storage reclamation, WAL/snapshot erasure and external-provider
deletion are different and remain unverified. Accepted external data cannot be
recalled; no zero-data-retention claim or remote deletion implementation follows.
Paid/private use remains disabled.

### M7 grounded earnings workflow

New fixture chats select the operator-owned `latest_earnings_v1` workflow,
with immutable `research-tools-v1/earnings-quotes-v1` prompt provenance.
Existing backend/legacy conversations retain their workflow. The native Rails
composer exposes approved workflow selection and lowering-only output/tool/time
caps; followups cannot raise the conversation ceiling or silently switch an
explicit listing/fiscal period.

The workflow resolves the exact authoritative latest event before selecting
its transcript/brief evidence. Each turn retrieves and rechecks evidence anew.
Output is deliberately **extractive**, not unverified financial paraphrasing:
strict JSON selects bounded verbatim quotations from supplied source IDs for
summary/results/outlook/risks. Event, listing and period must match. Transcript
forecast excerpts require a management label and cannot be labelled reported
results; briefs are provider interpretation, not independently verified facts.
Selection is labelled model synthesis; quotation support does not prove
real-world truth or general semantic correctness. Unknown publication history,
partial coverage and absent guidance/risks remain explicit.

Conflicts or insufficient material require empty-claim abstention, saved as
incomplete/no-evidence rather than a financial answer. Malformed/unsupported
claims fail explicitly before text publication while retaining settled known
usage. Source text and tools cannot change operator prompts, permissions or
limits. Native chat acceptance and separately authorized live-model quality
evaluation remain open; paid/private inference is still disabled.

### M6 authenticated research chat

Set the operator flag `RESEARCH_CHAT_ENABLED=1` to expose `/research_chats`;
it defaults to `0`, including Compose. This first UI is explicitly **original
fixture research only**: `SYNTH:ALPHA`, FY2026/Q3, zero external requests/cost.
It does not enable private evidence, OpenAI inference or live MCP access, and
never substitutes fixtures for a failed live request. Existing ERB/shadcn/Tailwind,
Turbo and Stimulus are retained; no React or dashboard rewrite.

Ordinary authenticated forms submit and stop runs without JavaScript. Owner
request keys deduplicate submissions; reloads, snapshots and reconnects are
read-only. Canonical encrypted messages, guarded source metadata and run/usage
receipts are independent of delivery. The page shows saved answers, tool
progress, UTC timing, uncertainty, token/cost reservations and explicit
partial/error states. The complete answer remains withheld until M4's
whole-output checks pass; this is not unvalidated token-by-token financial text.

Cable independently authenticates Warden's Rails session plus a server-side
chat lease. The random token stays in the encrypted Rails session, never HTML,
JavaScript or subscription URLs; only its SHA-256 digest is stored. The lease
expires after 30 minutes, is bound to the password digest, and is revoked and
remotely disconnected on logout. Owner subscription checks and five-second
access rechecks reject expired/cross-owner access. Snapshot polling cannot renew
an expired lease. An authenticated page visit or explicit submission may issue
a fresh chat lease; this is not global Devise idle timeout.
Same-origin WebSocket protection remains enabled.

Development/production Cable use pinned Redis with separate environment
prefixes. Web and the dedicated research worker share Compose's Redis URL.
Worker refresh invalidations are batched (0.3 seconds; terminal events immediate)
and contain no question/answer/evidence text. Redis remote-disconnect failure
cannot prevent ordinary logout: the persisted lease is revoked first, and
periodic access checks still close it. The client debounces authorized
Turbo snapshots and polls every five seconds for missed events. Disconnection
clears displayed messages; denied access stops polling and prevents a late
snapshot from restoring protected text. Redis delivery failure is logged;
canonical publication survives. Page responses are `no-store` and opt out of
Turbo caching. The composer stays outside refreshed state, and reconnect never
submits its draft.

Final Markdown uses pinned Kramdown plus an attribute-free Rails HTML allowlist.
Model-authored links/images/scripts are not navigable; source links permit only
exact HTTPS `equibles.com`, port 443, without credentials/query/fragment.
Questions and partial/error text are escaped. Semantic labels/live regions,
keyboard controls and existing themes are retained; no chat motion is required.

**M6-01 through M6-05 are locally verified; M6-06 is partial.** Browser fixture
completion crossed the real Redis/web/research-worker boundary. Reload/offline
recovery preserved two saved messages and one run without resubmitting a draft.
Ownership, session/logout/expiry, no-JavaScript forms, redaction and rendering
have automated tests. Native route coverage is now 20 cases; URL policy has four
Swift tests. Two isolated iOS signed-in chat attempts stopped at the
research-navigation selector, not a passing chat/session test. Android still
lacks Java/SDK tooling. Native keyboard, chat navigation, background/resume,
disconnect/reconnect and logout acceptance remain open; sharing a WebView
proves neither device acceptance nor a Swift/Kotlin-native chatbot. See
[native smoke evidence](native/smoke/disposable-rails.md).

Final local M6 verification (2026-11-07): **360 Rails tests / 4,191 assertions**
and **32 knowledge tests / 508 assertions**, with no failures or skips.
Development/production builds, eager loading and all Compose service health
checks passed. Browser logout/back navigation removed protected messages;
expiry stopped refresh and rejected a simulated late snapshot. Two disposable
accounts and their completed fixture records were removed. Isolated full-schema
row/index/trigger/rollback and populated-vector dump/restore passed, preserving
the original database volume; private backups remain protected and ignored.
This does not close native M6-06 or enable paid/private research.

### Rails-native conversational research assessment

Architectural direction, assessed 2026-11-07; **the M4 backend is implemented
locally; M5 adds durable state and M6 adds a fixture-only chat UI, not the complete
live research workflow**. Keep the
existing ERB/Turbo/Stimulus and shadcn/Tailwind surfaces. Build a small,
application-owned research orchestrator rather than a general-purpose agent
framework. Borrow CopilotKit's separation of UI, runtime and agent, not its code
or a mandatory frontend/runtime dependency.

Proposed flow:

```text
Authenticated Rails research page
  -> persist message/run and enqueue Active Job
  -> Sidekiq: application-owned agent loop
  -> OpenAI or Anthropic Claude adapter
  -> validate requested tool and reserve quota
  -> owner-scoped Equibles MCP client
  -> evidence and tool result back to model
  -> persisted answer + batched Turbo/Action Cable updates
```

GPT is an OpenAI model family; Claude is Anthropic's. Neither model supplies our
authorization, workflow policies or budgets. Official Ruby SDKs document both
providers; their current minimum Ruby versions admit this checkout's Ruby
version, but exact releases and dependency compatibility still require a locked
installation/test. Start with one provider, keep a narrow adapter for the other,
and do not silently switch providers because that changes data egress and spend.
The official MCP Ruby SDK documents Streamable HTTP clients; HTTP/SSE parser
dependencies, release compatibility and Equibles authentication remain to be
tested. Do not implement MCP framing or model HTTP streaming from scratch.

#### Existing foundation and concrete gaps

- Devise authenticates ordinary controller requests; M5 owner-scopes durable
  conversations/messages/runs/usage, and M6 independently authenticates Cable.
- Sidekiq research concurrency is isolated from maintenance. Jobs carry IDs,
  not credentials or raw transcripts.
- Cable now uses authenticated owner subscriptions and shared Redis in
  development/production. Controller authentication alone is insufficient.
- M6 reloads guarded canonical state on batched invalidations and polling;
  broadcasts alone are not durable delivery. Final Markdown and source links
  have separate restrictive policies.
- Existing encrypted owner credentials, explicit entitlement checks and bounded
  Equibles requests are useful patterns. The current snapshot is one USD quote,
  not a research corpus. Research retention, transcripts and model egress need
  their own reviewed scope; do not extend quote approval flags by implication.
- The synthetic research-policy lab demonstrates fixtures only. It is not a
  production prompt-injection detector, budget ledger or model evaluation suite.
- Hotwire Native shells load Rails HTML with their own cookie sessions. The
  same chat page is plausible without React/React Native, but streaming,
  background/resume, keyboard, cancellation and logout need real-device checks.

#### Native workflow and policy layer

Keep the first workflow narrow: latest earnings summary with follow-ups. Resolve
the latest call event before selecting its brief; use the exact-period transcript
when the newest approved brief is older. Record what was actually consulted and
link evidence. Unknown or missing material must be visible, not invented.

Store versioned workflow/prompt definitions, permitted tools and provider/model
configuration. Users may lower their limits; they must not raise operator caps.
Enforce limits outside the model: per-run input/output bounds, tool calls,
steps, elapsed time, concurrent runs, and daily owner/application spend.
Atomically reserve conservative capacity before each external call, settle
against reported usage, and retain uncertain reservations for reconciliation
after timeouts. Billing can exceed observed partial usage on cancellation or
ambiguous failures; local enforcement is not a guaranteed provider billing cap.
Equibles quota is also shared with REST/MCP clients outside this app, so check
provider rate limits and do not treat our local ledger as the global counter.

Use explicit queued/running/completed/failed/cancelled/interrupted states,
request deduplication and guarded state transitions. Check cancellation between
steps and during provider streaming where supported; do not promise refund of
work already accepted. Avoid replaying an entire charged run automatically after
a worker failure. Do not hold database locks throughout model/network calls.

Expose only reviewed research tools and validated arguments, even if MCP
discovery returns additional tools. Do not expose portfolio mutations, broker
credentials, arbitrary URLs, shell execution or trading tools. Treat retrieved
content as untrusted evidence. Validate citations against retrieved evidence IDs;
valid IDs alone do not prove that the generated claim is supported.

Test workflows with deterministic fake model/tool adapters by default: stale
brief fallback, missing transcript, unsupported citations, malicious tool
instructions, cross-owner access, quota races, duplicate jobs, cancellation,
disconnect/reconnect and worker interruption. Live evaluations should be
explicitly authorized, budgeted and scored for factual/citation support,
recency, latency and measured usage cost. They must not be mandatory CI calls.

AG-UI is optional interoperability, not a prerequisite for our own Hotwire UI.
MCP remains the external tool protocol. An internal, versioned event vocabulary
can represent run progress, text deltas, tool status and errors without claiming
AG-UI compatibility. Model API streams, MCP transport and browser streaming are
three separate connections.

Sources: [CopilotKit architecture](https://docs.copilotkit.ai/concepts/architecture),
[OpenAI Ruby SDK](https://github.com/openai/openai-ruby),
[Anthropic Ruby SDK](https://github.com/anthropics/anthropic-sdk-ruby),
[MCP Ruby client transports](https://ruby.sdk.modelcontextprotocol.io/client/transports/),
and [Rails 7.1 Action Cable](https://guides.rubyonrails.org/v7.1/action_cable_overview.html).

### M0 research pilot specification

Decision date: 2026-11-07. This is the implementation contract for the pending
M1-M9 work, **not an enabled feature or authorization for paid calls**.
No CopilotKit dependency, React rewrite, autonomous browsing, portfolio writes,
broker credentials, order execution or promised investment return is in scope.

#### Scope and baseline (M0-01, M0-06)

The first workflow is `latest_earnings_v1`: one exact listed company, its latest
concluded earnings call, results, outlook, risks and dated source links, with at
most three follow-up turns about that company/call. A fourth follow-up requires
a new conversation and budget check; daily ceilings still apply. Changing company/period requires a new
workflow selection. Questions outside scope receive an explicit explanation.
Research tools initially permitted for review are `GetEarningsCallEvent`,
`GetEarningsBrief` and `GetEarningsCallTranscript`; no other discovered tool is
implicitly authorized. An older approved brief must never stand in for the
latest call. If the bounded transcript pages are insufficient, report incomplete
coverage rather than implying the entire call was read.

Build the non-vector baseline first: exact owner/company/period/rights filters,
latest-event resolution, a directly selected brief or transcript, and PostgreSQL
full-text search for relevant passages. Return source IDs/line or turn references,
source and publication times where known, fiscal period, retrieval time and
coverage limitations. Raw financial figures must remain distinct from model
interpretation. Vector retrieval must use the same eligible corpus and filters.
Retain the simpler baseline unless hybrid retrieval improves recall@5 by at
least 5 percentage points without degrading citation/temporal correctness and
still meets latency/spend limits. No embeddings are required for an exact-period
document lookup.

#### Acceptance targets, not measured results (M0-04)

These are conservative application ceilings/targets, not provider entitlements.
They must be enforced by M5 and verified by M9 before live rollout. Users may
lower ceilings, never increase them. Each follow-up is separately budgeted and
also counts toward daily/conversation ceilings.

| Area | Initial acceptance contract |
| --- | --- |
| Test corpus | 24 original synthetic documents, 4 fictional companies x 3 fiscal periods x 2 document types; at least 120 passages, 2 owners, plus revision/expiry/unknown-time variants. No copied proprietary transcripts in CI. |
| Evaluation set | 40 fixed questions: 20 supported, 10 missing/conflicting/out-of-scope, 10 temporal/adversarial; preserve expected evidence IDs and availability times. |
| Retrieval | Recall@5 >=90% on supported questions; 100% exclusion of other-owner, revoked, expired and future-known evidence in boundary cases. Full-text baseline and vector/hybrid use identical corpus/query sets. |
| Answers | All material factual claims cite supplied evidence; >=95% claim-level support on human-reviewed evaluation, with zero wrong-company/quarter answers and zero invented numeric claims. Unsupported cases abstain or identify the gap. These are release criteria, not automatic guarantees. |
| Latest-period freshness | Re-resolve latest call metadata if older than 15 minutes; the actual source quarter/date remains explicit. Never require old-but-valid historical statements to masquerade as fresh observations. |
| Context and output | User message <=2,000 tokens; each model input <=10,000 tokens; cumulative model input <=12,000 tokens/run, output <=4,096 tokens/run including billable reasoning. Reject/trim safely before dispatch; no silent historical-context truncation. |
| Loop/network | <=4 model requests and <=6 provider data-tool calls/run; <=2 transcript pages of <=50 turns each; 90-second total run deadline; per-request deadlines cannot exceed remaining time. No automatic charged-run replay. |
| Concurrency | 1 active run/owner, 2 active application-wide; Equibles calls sequential within each run. These app limits do not replace the provider's shared account limits. |
| Equibles quota | <=30 research calls/owner/UTC day, or the smaller verified allowance/remaining capacity after existing REST/MCP use. Accepted error responses can consume quota. External clients share capacity: local reservations cannot guarantee their remaining quota. |
| Spend | <=$0.05 reserved/run, <=$0.20/conversation, <=$0.50/owner/UTC day and <=$1.00/application/UTC day across inference and embeddings; reserve/reconcile atomically. Live authorization remains off. |
| Ingestion | <=20,000 embedding input tokens/owner/UTC day; <=800 tokens/passage and <=50 overlap; count ingestion and query embeddings in the same spend ledger. No whole-database embedding. |
| Latency | Offline fixture workflow p95 <=2 seconds; authorized live pilot target first visible progress <=1 second and final answer p95 <=45 seconds over >=20 runs; 90-second deadline is mandatory even if targets fail. Measure cold/warm runs separately. |
| Disposal | Every retrieval excludes expired/revoked material at its validity check, even if cleanup has not run. Target deletion of primary text/vector/derived-cache rows within 15 minutes with a 5-minute scheduler; measure worker outages explicitly. Recheck before model egress/publication. No instantaneous backup, disk-page or provider erasure claim. |
| Pilot retention | Original synthetic corpus/chat/evaluations <=30 days; synthetic backup retention <=7 days. Real-source text/vector/answer/cache/backup retention remains disabled until provider-specific permission defines deadlines. |

#### Provider selection and unresolved gates (M0-02, M0-03)

Selected design candidates, verified against public documentation on 2026-11-07:

| Purpose | Selection and documented limits | Published standard USD price |
| --- | --- | --- |
| Inference | OpenAI Responses API, pinned `gpt-5.4-mini-2026-03-17`; 400,000 context window, 272,000 maximum input, 128,000 maximum output. Supports streaming, function calls and structured outputs. Start with low reasoning; the much smaller application ceilings above prevail. | Per 1M tokens: $0.75 input, $0.075 cached input, $4.50 output; regional processing adds 10% and is not included in this pilot estimate. |
| Embeddings | OpenAI `/v1/embeddings`, `text-embedding-3-small`; 1,536 dimensions, documented 8,192-token maximum input. Default 1,536 dimensions and cosine distance validated locally in M1; target deployments must recheck compatibility/restore. | $0.02 per 1M input tokens; no inference output charge for embeddings. |

Use one inference provider first, with no silent model/provider failover.
GPT-5-mini was considered but its current model page marks it deprecated; it is
not the selected pilot model. Claude/Anthropic remains a future alternative,
requiring its own access, price, retention, adapter and evaluation review.
No exact paid-account model access, rate tier, billing cap, regional routing,
or zero-data-retention approval has been established here.

At the full run ceilings, uncached inference costs
`12,000 * $0.75/1M + 4,096 * $4.50/1M = $0.027432`.
The entire 20,000-token daily embedding allowance adds $0.0004. These estimates
exclude tax, currency conversion, Equibles subscriptions, hosting, optional
provider tools and future price changes; no caching discount is assumed.
Revalidate prices before enabling calls. Reserve worst-case cumulative tokens
and retain uncertain charges after timeout/cancellation until reconciled;
local budgets are not a guarantee of the provider's final invoice.

Embedding provenance must include model ID, dimensions, chunker/normalization
version and source revision/hash. Never compare vectors from incompatible
versions; re-embedding is a separately budgeted migration, not an overwrite of
historical availability times. The embedding model has no dated snapshot listed;
detect/review service changes and retain that limitation in evaluations.

Proposed request policy: foreground Responses requests with explicit
`store: false`, no provider conversation/file/vector-store state, no background
mode and no hosted tools. Request in-memory rather than extended prompt caching
where supported and verify the actual model settings in M4. This is **not**
a zero-retention claim: OpenAI documents default abuse-monitoring retention
of up to 30 days, subject to legal/safety extensions; optional Zero Data
Retention/Modified Abuse Monitoring requires approval. Responses normally
stores application state for at least 30 days unless the storage control is
used; embeddings has no application state retention but still has default
abuse monitoring. Prompt caching has separate retention controls. API data is
not used for training by default unless opted in. Account settings and the
applicable service agreement must be checked before approved content is sent.

| Material/action | Evidence and decision | What unlocks live use |
| --- | --- | --- |
| Original synthetic fixtures, local fake inference | Safe implementation/test starting point; no external calls or proprietary corpus needed. | M1-M9 offline work may proceed now. |
| Earnings event/brief/transcript read | Published REST/MCP research tools exist; earlier quote probes do not prove earnings access for this account or exact plan identity. Free/Plus first; no automatic Pro upgrade. | Verify account plan, actual endpoint/tool availability and smallest bounded contract probe after review. |
| Transcript/brief text storage and full-text index | Exact permitted duration, scope and source-specific exceptions are unresolved. | Written terms/support clarification covering this private app, text, indexes, caches and deletion. |
| Embeddings of source text and queries | Embeddings are derived source artifacts; vector storage and sending text to an embedding service are distinct permissions. Neither is implied by quote-only entitlements. | Approval for derivatives, OpenAI processing, storage/expiry and versioned re-embedding. |
| Inference egress | Source excerpts, ticker/period and minimized research questions only are proposed; **real-source egress remains disabled pending recorded permission scope**. No API keys, passwords, broker credentials, account IDs, holdings, trade history or unrelated user records in prompts/traces. | Source processing permission plus owner-approved OpenAI account, spend, retention/region and request settings. Synthetic paid tests also need explicit account/spend authorization. |
| Derived answers/private display | Public terms describe supported AI clients but do not settle this app's exact Free/Plus derived-output retention/use case. Attribute Equibles beside citations; no promised returns. | Clarify private-owner use versus showing data/answers to reviewers or other users; record dataset exceptions and retention. |
| Public/multi-user redistribution | Section 6's general active-Pro distribution grant is not a Free/Plus grant and excludes quotes, daily prices, options and FINRA datasets. It does not permit downstream bulk/API feeds. | Dataset-specific permission or applicable written agreement; otherwise keep this surface off. |
| Backups, logs and revocation | No agreed real-source backup window or restore erasure procedure; local deletion cannot remove provider logs/backups. | Approved deadlines for raw text, vectors, derived answers/caches/logs/backups and post-restore deletion replay; M8 verification. |

Approval details still to record (no support request sent by this app):
for a single-owner educational
Free/Plus Rails app, may event metadata, transcripts and approved briefs be
retrieved via MCP/REST, cached and full-text indexed; embedded by OpenAI and
stored in PostgreSQL; sent as bounded excerpts to OpenAI under the documented
default logging policy; and summarized with Equibles attribution? Specify allowed
retention for each raw/derived/backup artifact, expiry/revocation obligations,
dataset exceptions and whether private reviewer access changes the license.
If Free/Plus cannot cover a particular action, request its exact restriction
and available alternative, rather than assuming a wholesale plan upgrade.

Permission update received 2026-11-07: the user reports that Equibles permission
has been granted. This records the user's confirmation, not independent review
of a provider approval. The approved actions, applicable plan/datasets, retention
and backup conditions, approval reference and actual approval date have not been
provided. The matrix above identifies those unrecorded details; it does not
assert that Equibles denied permission or that every action was approved.

M0-01/04/05/06 are specified. **M0-02 remains partial** (selection/public facts
complete, account controls and approved egress unverified); **M0-03 is partial**
(permission reported, exact scope and conditions still to record). No paid
inference or embedding call was made, and existing entitlements remain
default-disabled. This report alone does not authorize public redistribution,
set retention periods, enable model egress or establish OpenAI account/spend
approval. Offline original-fixture work can continue.

Sources: [inference model](https://developers.openai.com/api/docs/models/gpt-5.4-mini),
[deprecated alternative](https://developers.openai.com/api/docs/models/gpt-5-mini),
[embedding model/pricing](https://developers.openai.com/api/docs/models/text-embedding-3-small),
[embedding dimensions/limits](https://developers.openai.com/api/docs/guides/embeddings),
[API data controls](https://developers.openai.com/api/docs/guides/your-data),
[prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching),
[Equibles research documentation](https://equibles.com/docs) and
[Equibles terms, sections 5-6](https://equibles.com/legal/terms).

#### Dependency order and permitted parallel work (M0-05)

```text
M0 scope/thresholds ---------> offline fixtures + non-vector baseline
M0 model selection ---------> M4 model/tool adapters (stubbed first)
M0 real-data permissions ---> any real-source ingestion or external model egress
M1 restored pgvector DB ----> M2 vector ingestion ---> M3 indexed retrieval
M4 adapters + M5 limits ----> any authorized paid agent run
M5 durable owner/run state -> M6 authenticated streaming
M3 + M4 + M5 + M6 ----------> M7 end-to-end research workflow
M8 tested disposal --------> retention of licensed source/derived material
M9 verifies each slice ----> feature-flagged pilot acceptance
```

Non-vector M3 behavior, original fixtures, fake-provider evaluations and UI
scaffolding need not wait for pgvector or external permissions. M1 can be
prepared/tested in an isolated restored database independently. M8's schema and
expiry guards must be designed with M2, not added after licensed data is stored.
M9 testing accompanies each workstream, rather than beginning only at the end.
All dependencies above are prerequisites, not evidence that the slices exist.

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
and open `/portfolio_examples`. This public demo is deliberately isolated from private
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
