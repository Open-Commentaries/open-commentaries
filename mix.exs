defmodule TextServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :text_server,
      version: "0.0.3",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers() ++ [:rambo],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {TextServer.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:amqp, "~> 3.3"},
      {:bcrypt_elixir, "~> 3.0"},
      {:bumblebee, "~> 0.4.2"},
      {:data_schema, "~> 0.5.0"},
      {:earmark, "~> 1.4.34"},
      {:ecto_psql_extras, "~> 0.6"},
      {:ecto_sql, "~> 3.6"},
      {:esbuild, "~> 0.7", runtime: Mix.env() == :dev},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_aws, "~> 2.0"},
      {:exla, "~> 0.6.1"},
      {:floki, ">= 0.30.0", only: :test},
      {:gen_smtp, "~> 1.2.0"},
      {:gettext, "~> 0.18"},
      {:hackney, "~> 1.17"},
      {:html_sanitize_ex, "~> 1.4"},
      {:iteraptor, "~> 1.12.0"},
      {:jason, "~> 1.3"},
      {:nx, "~> 0.6.2"},
      {:oban, "~> 2.13"},
      {:panpipe, "~> 0.3"},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_html, "~> 3.0"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix_live_reload, "~> 1.4", only: :dev},
      {:phoenix_live_view, "~> 0.19"},
      {:phoenix_view, "~> 2.0"},
      {:phoenix_pubsub, "~> 2.1.3"},
      {:phoenix_swoosh, "~> 1.1"},
      {:phoenix, "~> 1.7"},
      {:plug_cowboy, "~> 2.5"},
      {:postgrex, "~> 0.16.3"},
      {:rambo, "~> 0.3.4"},
      {:recase, "~> 0.5"},
      {:scrivener_ecto, "~> 2.7"},
      {:sweet_xml, "~> 0.7.1"},
      {:swoosh, "~> 1.3"},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:tesla, "~> 1.4"},
      {:toml, "~> 0.7"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      # See https://elixirforum.com/t/squashing-schema-migrations/26184/15 for
      # guidance on squashing migrations
      "ecto.setup": [
        "ecto.create",
        "ecto.load -d priv/repo/20230828_schema.sql -f --skip-if-loaded",
        "ecto.migrate"
      ],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"]
    ]
  end
end
