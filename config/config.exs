# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :text_server,
  ecto_repos: [TextServer.Repo]

config :text_server, TextServer.Repo, types: TextServer.Postgrex.Types

# Configures the endpoint
config :text_server, TextServerWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: TextServerWeb.ErrorHTML, json: TextServerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TextServer.PubSub,
  live_view: [signing_salt: "Uy4jmRfq"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :text_server, TextServer.Mailer, adapter: Swoosh.Adapters.Local

# Configures Oban for running background jobs (like
# parsing uploaded/changed versions)
config :text_server, Oban,
  repo: TextServer.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [default: 10]

# Swoosh API client is needed for adapters other than SMTP.
config :swoosh, :api_client, false

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.14.0",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :tailwind,
  version: "3.3.3",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

config :tesla, adapter: Tesla.Adapter.Hackney

config :nx, default_backend: EXLA.Backend

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
