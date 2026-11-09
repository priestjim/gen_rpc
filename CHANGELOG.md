# Changelog

Below is a non-exhaustive list of changes between `gen_rpc` versions.

## Unreleased

## 3.0.1

- Acceptor processes are not registered under a name by default, since each connection created a new atom that is never garbage collected. Set `named_acceptors` to `true` to name them after the connected peer
- Fix the acceptor and the client crashing with a `function_clause` error when they receive an exit signal from another process. They now stop with the reason of the signal

## 3.0.0

- Deprecate support for Erlang < 25.0 and support up to Erlang/OTP 29
- Support monitoring nodes with `gen_rpc:monitor_node/2`
- Support EC SSL certificates, the RSA test certificates (`priv/ssl`) were removed
- Support cookie per node configuration
- Support external cookie validation mechanism
- Support custom TCP socket options for the whole server and client with the `tcp_server_options` and `tcp_client_options` settings, merged with the defaults
- Support keepalive that actively keeps a client connection alive, configured by `keepalive_interval`
- SSL now enforces TLS 1.3 only, with AEAD cipher suites, an EC-only key exchange and ECDSA-only signature algorithms (RSA certificates are rejected). The key exchange prefers hybrid post-quantum (ML-KEM) groups where available. TLS 1.2 and older and the legacy cipher suites are not supported anymore
- Continuous integration moved from Travis CI to GitHub Actions and the Docker integration tests use Docker Compose (`make integration`)
- The `authenticate_server/1` driver callback has been replaced by `authenticate_to_server/2` and drivers
  need to implement `getstat/2`, `recv/2`, `close/1` and `verify_peer/2`. The authentication handshake itself is shared by the
  drivers, see `gen_rpc_driver:authenticate_to_server/3` and `gen_rpc_driver:authenticate_client/4`
- Clients connect and authenticate before their process is started, so a node that is slow to answer does not block the clients
  of other nodes. Concurrent requests for the same client share one connection attempt
- Casts, `abcast`, `sbcast` and `eval_everywhere` to a running client no longer spawn a process
- The send timeout of a client socket is only set when it changes
- Debug logging no longer builds its arguments when debug logging is disabled
- Tests use the `peer` module instead of the deprecated `slave` module

## 2.1.0

- Support multiple connections per node using aribtrary keys.

- Add support for Linux and Darwin/macOS custom keepalive settings to detect socket issues
  faster.

## 2.0.1

- Support external node driver/port discovery.

## 2.0.0

This release boasts a major rengineer/refactor of `gen_rpc` that includes quite a few new features:

- The server and acceptor FSMs have been converted to `gen_statem` to follow Erlang's best practices
  and development. As a result, **support for Erlang releases older than 19.1 has been dropped**.

- Specific options, leveraging Erlang 19, have been enabled such as off-heap mailboxes for client and acceptor,
  and higher priorities for all `gen_rpc` processes.

- Ports are not dynamically assigned anymore as it shows that, after some research, offers no additional benefits
  to having a static port listener. That means less processes to supervise and less moving parts where something can
  go wrong.

- Support for SSL has been added. Please refer to the [README](README.md#ssl-configuration) for more information on
  how to use it.

- Module version control support has been added, effectively allowing you to only make RPC calls to nodes that
  run specific versions of modules.

- `lager` support has been **dropped** in favor of the logging backend-agnostic library `hut`, in order to better support
  Elixir installations. The test suite and development profiles still use lager but this doesn't interfere with production
  deployments of `gen_rpc`.

- Tests have been updated to test more edge cases, including new SSL functionality.

- Some options in `gen_rpc.app.src` have changed names to better describe what they do. Again, pleaserefer to the README to
  verify your preexisting settings are consistent with their new names.

- Various smaller bugs have been fixed and various responses have been massaged for consistency.

## 1.0.2

- Implemented blacklisting/whitelisting of modules available for RPC.

- Implemented abcast and sbcast support.

## 1.0.1

- Updated documentation

- Updated/optimized various TCP options

- Updated tests to include more edge cases

- Support client-configurable listener port per remote node

- Small code refactoring and cleanup

## 1.0.0

This release drops the hybrid RPC/TCP approach and uses a separate TCP listener to emulate initial RPC communication.
In addition, this release includes:

- Updated documentation

- Added integration tests using Docker
