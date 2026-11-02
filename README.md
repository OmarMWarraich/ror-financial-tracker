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
