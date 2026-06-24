# Reach architecture/smell policy for `mix reach.check --arch --smells`.
#
# `:arch` starts permissive (no layer/boundary policy yet) so reach gates on
# cross-function smells only. Populate layer/boundary rules here as cartouche's
# module architecture solidifies (substrate vs signer backends vs RPC vs codecs).
# See the `elixir:reach` skill / hexdocs for the policy DSL.
#
# `smells.ignore.paths` scopes the smell detector to hand-written runtime code.
# Excluded are the build-time code generator and its generated output, where the
# flagged patterns are INHERENT to metaprogramming, not fixable defects:
#
#   * lib/mix/cartouche.gen.ex — the generator. Its `String.to_atom/1` calls
#     CREATE the identifiers (function/variable names) of the code it emits;
#     `String.to_existing_atom/1` is impossible for a not-yet-defined function,
#     so the "unsafe atom creation" smell has no valid fix here. Its repeated
#     map shapes are codegen templates. These lines already carry
#     `# sobelow_skip ["DOS.StringToAtom"]` + `HERE BE DRAGONS` — the project
#     already ruled them intentional-and-unavoidable for the sibling linter.
#   * lib/cartouche/contract/** — generated contract bindings (the generator's
#     output, e.g. i_console.ex's 383x ABI-descriptor maps). `.credo.exs`
#     already excludes this dir from the Specs check for the same reason.
#
# This is linter SCOPING (the codegen isn't hand-written runtime code), not a
# finding baseline: no per-finding fingerprints, no churn on line shifts. Every
# smell in hand-written `lib/cartouche/**` runtime code is fixed for real.
[
  smells: [
    ignore: [
      paths: [
        "lib/mix/cartouche.gen.ex",
        "lib/cartouche/contract/**"
      ]
    ]
  ]
]
