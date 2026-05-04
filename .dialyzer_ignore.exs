[
  # CloudKMS signers wrap GoogleApi.CloudKMS.* + Goth, both excluded from the
  # PLT via mix.exs `:plt_ignore_apps` (the GCP cluster otherwise OOMs the
  # 16GB CI runner during PLT construction). The `Code.ensure_loaded?/1`
  # guard at the call sites makes runtime correctness independent of whether
  # the optional GCP deps are present.
  {"lib/cartouche/signer/cloud_kms.ex", :unknown_function},
  {"lib/cartouche/solana/signer/cloud_kms.ex", :unknown_function}
]
