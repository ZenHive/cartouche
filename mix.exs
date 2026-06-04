defmodule Cartouche.MixProject do
  use Mix.Project

  def project do
    [
      app: :cartouche,
      version: "0.2.2",
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
        extras: ["README.md", "CHANGELOG.md"],
        # CHANGELOG entries reference hidden generated modules (e.g.
        # `Cartouche.Contract.IConsole`, which has `@moduledoc false`) as
        # historical narrative — not as API documentation. ex_doc otherwise
        # warns and `mix docs --warnings-as-errors` (the pre-commit hook)
        # blocks the commit. Skip on CHANGELOG.md only; README and source
        # docstrings remain strict.
        skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
      ],
      # plt_*_path pin keeps the PLT outside _build/ so CI can cache it
      # independently of the deps cache (which invalidates on mix.lock).
      #
      # plt_add_deps: :apps_direct skips transitive dep recursion (default is
      # :app_tree). Tidewave/bandit's dev-only HTTP stack (plug, finch, mint,
      # gun, cowlib, etc.) is not in lib/'s call graph and bloats the PLT.
      #
      # plt_ignore_apps strips two clusters on top of :apps_direct:
      #   1. GCP cluster (google_api_cloud_kms + google_gax + goth + tesla +
      #      jose) — direct/optional runtime deps for the CloudKMS signer
      #      (~600 modules). Trade-off: dialyzer won't type-check
      #      Cartouche.Signer.CloudKMS calls into GoogleApi.* / Goth —
      #      acceptable since CloudKMS is an optional signer with a narrow
      #      call surface (Goth.Token + GoogleApi.CloudKMS.*).
      #   2. Dev-only direct deps (bandit, tidewave) — pulled in via the
      #      `tidewave` mix alias, never called from lib/. Including them
      #      means every Tidewave or Bandit minor bump invalidates the
      #      cartouche PLT, dragging incremental rebuilds back into the
      #      20+ minute range.
      dialyzer: [
        plt_add_deps: :apps_direct,
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts",
        # :mint added so dialyzer can resolve `Mint.Types.status/0` /
        # `Mint.Types.headers/0` referenced from `deps/finch/lib/finch/response.ex`.
        # Finch 0.22 surfaces those as transitive types — `:apps_direct` skips
        # transitives, so without this entry dialyzer reports 3 `unknown_type`
        # warnings on finch's response struct.
        plt_add_apps: [:mix, :ex_unit, :mint],
        plt_ignore_apps: [
          :google_api_cloud_kms,
          :google_gax,
          :goth,
          :tesla,
          :jose,
          :bandit,
          :tidewave
        ]
      ],
      test_coverage: [ignore_modules: [Cartouche.Contract.IConsole]],
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
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false},
      {:jason, "~> 1.4.5"},
      # Bumped to ~> 3.1 (2026-05-08). Decimal 3.0 tightens IEEE 754 decimal128
      # bounds (precision 28 → 34, exponent capped at ±6_144, CVE-2026-32686
      # DoS-bounded parsing) and fixes `to_integer("0.0")` infinite loop. No
      # changes to rounding modes, comparison, or normalization semantics —
      # safe for wei/fee token math (uint256 max ~78 digits << 6_178 string
      # cap). See https://github.com/ericmj/decimal/blob/main/CHANGELOG.md.
      {:decimal, "~> 3.1"},
      {:finch, "~> 0.22"},
      {:google_api_cloud_kms, "~> 0.43.0", optional: true},
      {:ex_sha3, "~> 0.1.5"},
      {:curvy, "~> 0.3.1"},
      {:goth, "~> 1.4.5", optional: true},
      {:ex_rlp, "~> 0.6.0"},
      # Promoted from transitive (via :hieroglyph) to direct so consumer
      # mix.exs files don't need to add it to use Cartouche.describe/0,1,2.
      {:descripex, "~> 0.7.0"},
      # Formerly `{:abi, path: "../abi"}`. The fork has been renamed and
      # published on hex.pm as `hieroglyph` 1.0.0 (hex package name only;
      # module namespace remains `ABI`). Switching to hex unblocks
      # `mix hex.publish` here (which rejects path/git deps).
      # `override: true` dropped at publish time — no transitive dep
      # pulls `hieroglyph` or `:abi`, so nothing needs overriding, and
      # hex rejects overrides on published packages.
      {:hieroglyph, "~> 1.4.0"},
      {:junit_formatter, "~> 3.4.0", only: [:test]}
    ] ++ zenhive_dev_deps()
  end

  # ZenHive dev-branch only. Never merged back to main (tracks upstream).
  # PR branches fork from `main` so these never appear in any upstream diff.
  defp zenhive_dev_deps do
    [
      {:styler, "~> 1.11.0", only: [:dev, :test], runtime: false},
      {:ex_unit_json, "~> 0.5.0", only: [:dev, :test], runtime: false},
      {:dialyzer_json, "~> 0.2.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7.18", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14.1", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23.0", only: [:dev, :test], runtime: false},
      {:meck, "~> 1.2.0", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5.1", only: [:dev, :test], runtime: false},
      {:ex_ast, "~> 0.12", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.7", only: [:dev, :test], runtime: false},
      {:tidewave, "~> 0.5.6", only: :dev},
      {:bandit, "~> 1.11.0", only: :dev}
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
      integration: ["test.json --only integration"],
      manifest: ["descripex.manifest --pretty --output api_manifest.json --app cartouche"]
    ]
  end
end
