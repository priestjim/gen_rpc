# Repository Guidelines

## Project Structure & Module Organization
- `src/` holds the OTP application and supervisors (`gen_rpc.app.src`, `gen_rpc_*.erl`), with supporting drivers under `src/driver/`.
- `include/` exposes shared headers; ERL specs imported by tests live in `test/include/`.
- `priv/` contains runtime assets such as the sample EC SSL certificates under `priv/ec_ssl/`.
- Common Test suites reside in `test/ct/`, configuration fixtures in `test/gen_rpc.*.config`, and integration helpers under `test/integration/`.

## Build, Test, and Development Commands
- `make all` compiles the project with `rebar3` in the `dev` profile.
- `make test` runs Common Test suites (`ct -c`) and aggregates coverage as defined in `test/gen_rpc.coverspec`.
- `make dialyzer` builds the PLT in `_plt/` (if needed) and runs static analysis.
- `make shell` or `make shell-slave` launches named nodes using the configs in `test/`.
- `REBAR_PROFILE=dev ./rebar3 do xref` is useful for cross-reference checks when iterating on APIs.

## Coding Style & Naming Conventions
- Follow Erlang conventions used in `src/`: modules are snake_case prefixed with `gen_rpc_`, public APIs live in `gen_rpc.erl`.
- Indent with hard tabs configured to 4 columns; avoid manual alignment or trailing whitespace.
- Keep functions small, avoid deeply nested `case` chains, and prefer descriptive atoms over comments.
- When adding specs, place headers in `include/` and regenerate with `make spec` if typer annotations are needed.

## Testing Guidelines
- Use Common Test; new suites belong in `test/ct/` and should be named `feature_SUITE.erl`.
- Exercise distributed scenarios by reusing helpers in `gen_rpc_test_helper.erl` and the node configs in `test/`.
- Run `make test` before requesting review; for static coverage goals, inspect `log/ct/` reports and update affected suites.
- Integration smoke tests can be run with `make integration NODES=3` (Docker required), mirroring CI expectations.

## Commit & Pull Request Guidelines
- Base branches off `develop`, keep each commit focused, and ensure the change passes `make test dialyzer`.
- Craft commit titles ≤72 characters, blank line, then detailed body; avoid auto-closing keywords.
- Pull requests should summarize intent, reference tickets, and mention any config changes (e.g., certificates or node names).
- Include proof of validation (command output or logs) when touching networking, SSL, or client configuration.

## Security & Configuration Tips
- Store environment-specific cookies outside the repo and reference them via `sys.config`; sample keys in `priv/ec_ssl/` are for testing only.
- When running multiple nodes locally, start `epmd` via `make epmd` or ensure it is already resident to avoid connection hangs.
