# gen_rpc Codebase Guide

## Build/Lint/Test Commands
- `make` - Build the project
- `make test` - Run all tests with coverage
- `make dist` - Run tests, dialyzer, xref
- `make shell-master` - Start master node for testing
- `make integration` - Run integration tests with Docker

## Running Single Tests
Use rebar3 directly: `rebar3 ct -c -suite test/ct/local_SUITE`

## Code Style Guidelines
- Erlang/OTP >= 21.0
- Follow standard Erlang naming conventions (snake_case for functions, camelCase for records)
- Use `gen_server` patterns for state management
- Error handling with `{badrpc, Error}` and `{badtcp, Error}` return values
- All modules should have proper `-spec` declarations
- Use `hut` for logging
- Prefer explicit pattern matching over `case` expressions where possible
- Use `-ifdef`/-endif for conditional compilation

## Testing
- Tests use Common Test (CT) framework
- All test suites are in `test/ct/`
- Integration tests in `test/integration/`