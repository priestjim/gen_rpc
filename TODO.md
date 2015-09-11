# gen_rpc TODO

This is a list of pending features or code technical debt for `gen_rpc`:

- Implement SSL connectivity
- Implement block_call, async_call/yield, multicall, eval_everywhere, pinfo
- Catch exit signals from `calls` and send them back as replies to callers
- Extract commonly used functions into `helper` module and use typespecs to enforce type checking
- Update typespecs in project