%Doctor.Config{
  # Mix.Tasks.Cartouche.Gen builds AST literals via `def unquote(name)(args)`
  # inside `quote do ... end` blocks for the contract modules it emits. Doctor's
  # source-level AST walker counts those literals as if they were defs of the
  # Mix task itself (BEAM introspection confirms only run/1 is actually exported),
  # producing 23 false-positive missing-doc warnings. Excluding the module silences
  # the false positive; the @moduledoc stays in source for `mix help cartouche.gen`.
  # TODO(upstream-doctor): drop once Doctor's AST walker handles `def unquote(name)(args)`
  # inside `quote do ... end` blocks. Intentionally untracked in ROADMAP — this is an
  # upstream Doctor limitation we can't fix locally.
  ignore_modules: [Mix.Tasks.Cartouche.Gen],
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 100,
  min_overall_doc_coverage: 100,
  min_overall_moduledoc_coverage: 100,
  min_overall_spec_coverage: 100,
  exception_moduledoc_required: true,
  raise: false,
  reporter: Doctor.Reporters.Full,
  struct_type_spec_required: true,
  umbrella: false,
  failed: false
}
