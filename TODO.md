# gen_rpc TODO

This is a list of pending features or code technical debt for `gen_rpc`:

- Implement SSL connectivity
- Implement block_call, async_call/yield, multicall, eval_everywhere, pinfo
- Extract commonly used functions into `helper` module and use typespecs to enforce type checking
- Update typespecs in project
- Remove RPC call dependency and switch from rpc:call to a `gen_tcp` listener
- Implement parse transforms to transparently switch specific RPC library calls (i.e. `rpc:call` and `rpc:cast`) to `gen_rpc`