# `:debug_namespace` is excluded alongside `:integration` because the archive
# node deliberately serves no `debug_*` methods (DoS surface). Opt in with
# `mix test --only debug_namespace` against a node that enables them — see
# `test/rpc_debug_namespace_test.exs`.
ExUnit.start(exclude: [:integration, :debug_namespace, :dev_node])
