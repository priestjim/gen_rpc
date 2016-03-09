# gen_rpc TODO

This is a list of pending features or code technical debt for `gen_rpc`:

- Implement SSL connectivity, including CN-based authentication
- Implement whitelisting/blacklisting of RPC modules and functions
- Implement per-id-and-node tuple connection sharing to spread workload on multiple mailboxes per node
- Implement sbcast and abcast support
- Implement static port range allocation (instead of listening to 0) to adhere to potential corporate firewall rules
- Implement support for client-configurable TCP port per node in case multiple `gen_rpc` nodes are running on the same server.