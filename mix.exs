defmodule Cartouche.MixProject do
  use Mix.Project

  def project do
    [
      app: :cartouche,
      version: "0.1.3",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "Cartouche",
      description: "Lightweight Ethereum and Solana RPC client for Elixir",
      source_url: "https://github.com/zenhive/cartouche",
      docs: [
        main: "readme",
        extras: ["README.md", "CHANGELOG.md"]
      ],
      # TODO(Task 42)/TODO(Task 41): drop once generator-side fixes land
      # and IConsole is regenerated — see `.dialyzer_ignore.exs` header.
      dialyzer: [ignore_warnings: ".dialyzer_ignore.exs"],
      package: package()
    ]
  end

  # ZenHive dev-branch only: preferred envs for our tooling.
  def cli do
    [preferred_envs: ["test.json": :test, "dialyzer.json": :dev, integration: :test]]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*", "CHANGELOG*"],
      maintainers: ["ZenHive"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/zenhive/cartouche",
        "Changelog" => "https://hexdocs.pm/cartouche/changelog.html"
      }
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Cartouche.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # zenhive/dev override: bumped from upstream's ~> 0.31.1 so :reach (needs
      # makeup_elixir ~> 1.0) can resolve. Never cherry-picked into PR branches
      # (they fork from `main` and keep upstream's pin).
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:jason, "~> 1.4.1"},
      {:finch, "~> 0.19"},
      {:google_api_cloud_kms, "~> 0.43.0", optional: true},
      {:ex_sha3, "~> 0.1.4"},
      {:curvy, "~> 0.3.1"},
      {:goth, "~> 1.4.3", optional: true},
      {:ex_rlp, "~> 0.6.0"},
      # Formerly `{:abi, path: "../abi"}`. The fork has been renamed and
      # published on hex.pm as `hieroglyph` 1.0.0 (hex package name only;
      # module namespace remains `ABI`). Switching to hex unblocks
      # `mix hex.publish` here (which rejects path/git deps).
      # `override: true` dropped at publish time — no transitive dep
      # pulls `hieroglyph` or `:abi`, so nothing needs overriding, and
      # hex rejects overrides on published packages.
      {:hieroglyph, "~> 1.4"},
      {:junit_formatter, "~> 3.3", only: [:test]}
    ] ++ zenhive_dev_deps()
  end

  # ZenHive dev-branch only. Never merged back to main (tracks upstream).
  # PR branches fork from `main` so these never appear in any upstream diff.
  defp zenhive_dev_deps do
    [
      {:styler, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_unit_json, "~> 0.4", only: [:dev, :test], runtime: false},
      {:dialyzer_json, "~> 0.2", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_ast, "~> 0.8", only: [:dev, :test], runtime: false},
      {:reach, "~> 1.5", only: [:dev, :test], runtime: false},
      {:rename, "~> 0.1.0", only: :dev},
      {:tidewave, "~> 0.5", only: :dev},
      {:bandit, "~> 1.10", only: :dev}
      # :boxart intentionally omitted — conflicts with upstream ex_doc 0.31.1
      # (needs makeup_elixir ~> 1.0, ex_doc pulls ~> 0.14). Terminal --graph
      # rendering is optional; text/json output still works for all reach.* tasks.
    ]
  end

  # ZenHive dev-branch only. Tidewave alias — port registered in
  # ~/.claude/tidewave-ports.md. Never merged back to main.
  defp aliases do
    [
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4013) end)'"
      ],
      integration: ["test.json --only integration"]
    ]
  end
end
