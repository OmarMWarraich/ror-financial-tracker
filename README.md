# Financial Tracker

A Ruby on Rails application for maintaining a stock watchlist and following other users' portfolios. This is a tracking app, not a brokerage: it does not execute trades or record holdings, transactions, or investment returns.

## Features

- Account registration, sign-in, and password recovery through Devise.
- Stock search by ticker, displaying company names and prices through a legacy IEX Cloud integration.
- Personal portfolios with add/remove controls and a 10-stock limit in the tracking eligibility checks.
- User search by first name, last name, or email, with friend add/remove controls.
- Viewing other users' tracked stocks and adding them to your own portfolio.
- Turbo-driven search results, portfolio updates, and flash messages.

> **Stock lookup limitation:** The app still targets `https://cloud.iexapis.com/v1` using `iex-ruby-client`. IEX Cloud retired in 2024, so new stock lookups need a replacement data provider or stubbed responses for local development. Historical credentials alone will not restore the service. Stored prices are not automatically refreshed.

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

The committed lockfile currently lists only `x86_64-linux`. If Bundler rejects your platform on macOS or another architecture, add it before installing:

```sh
bundle lock --add-platform "$(ruby -e 'puts Gem::Platform.local')"
bundle install
```

This updates the lockfile; review that change before committing it.

### Credentials

Obtain the existing Rails master key from the project maintainer and place it in `config/master.key`, or supply it through `RAILS_MASTER_KEY`, to decrypt the committed [config/credentials.yml.enc](config/credentials.yml.enc). Never commit the key or API tokens.

The current [app/models/stock.rb](app/models/stock.rb) reads this legacy structure from encrypted Rails credentials:

```yaml
iex_client:
	publishable_token: YOUR_LEGACY_PUBLISHABLE_TOKEN
	secret_token: YOUR_LEGACY_SECRET_TOKEN
```

Edit credentials with your configured editor, for example:

```sh
EDITOR="code --wait" bin/rails credentials:edit
```

These keys document the existing integration, not a working quote-service setup. Do not replace the shared credentials or generate a new master key for the existing encrypted file. Missing `iex_client` configuration can raise an error when the app constructs its API client. The app does not include dotenv; environment variables must be supplied by your shell or deployment environment rather than merely placed in a `.env` file.

### Prepare the Database and Start Rails

```sh
bin/rails db:prepare
bin/rails server
```

Open <http://localhost:3000> and register an account. The default database names are `myapp_development` and `myapp_test`. [db/seeds.rb](db/seeds.rb) currently contains no sample records or preconfigured accounts.

For subsequent setup or environment refreshes, [bin/setup](bin/setup) installs/checks dependencies, prepares the database, clears logs and temporary files, and requests an application restart.

## Usage

- **My Portfolio** (`/my_portfolio`): search for a ticker and manage tracked stocks. New ticker lookups are subject to the provider limitation above.
- **My Friends** (`/my_friends`): search registered users and manage your friends list.
- **User Portfolio** (`/users/:id`): inspect another user's tracked stocks.
- **Health Check** (`/up`): Rails boot health endpoint, not a check of database or quote-provider connectivity.

See [config/routes.rb](config/routes.rb) for the complete route definitions.

## Tests

With PostgreSQL running and a separate test database configured:

```sh
RAILS_ENV=test bin/rails db:prepare
bin/rails test
bin/rails test test/models/stock_test.rb
bin/rails test:system
```

The test suite uses Minitest and fixtures. The stock model test is currently a generated placeholder; do not treat a passing run as proof that live quote lookup works. System tests are configured to use Chrome through Selenium, so browser-based tests require Chrome and an available compatible driver. See [test/test_helper.rb](test/test_helper.rb) and [test/application_system_test_case.rb](test/application_system_test_case.rb).

## Docker and Production

[Dockerfile](Dockerfile) builds a production image with precompiled assets and a non-root runtime user:

```sh
docker build -t financial-tracker .
docker run --rm -p 3000:3000 \
	-e RAILS_MASTER_KEY \
	-e DATABASE_URL \
	financial-tracker
```

Export `RAILS_MASTER_KEY` and `DATABASE_URL` in your shell before running the container. Use a PostgreSQL URL reachable **from the container**; `localhost` inside the container is not your host machine. The image does not include a PostgreSQL server, and the entrypoint runs `db:prepare` before starting Rails.

Production forces HTTPS. Deploy behind an appropriately configured TLS-terminating reverse proxy; the plain HTTP port mapping above is not a complete production deployment. Configure production mail delivery before relying on password recovery, and replace the legacy quote provider before expecting stock search to work.

Relevant runtime settings:

| Setting | Purpose |
| --- | --- |
| `RAILS_MASTER_KEY` | Decrypts Rails credentials when the key file is unavailable. |
| `DATABASE_URL` | Supplies a PostgreSQL connection URL, overriding matching database configuration values. |
| `MYAPP_DATABASE_PASSWORD` | Password for the default production `myapp` database role when not overridden by the connection URL. |
| `RAILS_MAX_THREADS` | Database pool size and Puma thread configuration; defaults to 5. |
| `RAILS_LOG_LEVEL` | Production log level; defaults to `info`. |

See [config/environments/production.rb](config/environments/production.rb), [config/database.yml](config/database.yml), and [bin/docker-entrypoint](bin/docker-entrypoint) for deployment behavior. The build's `SECRET_KEY_BASE_DUMMY` is only for asset precompilation, not a substitute for runtime credentials.
