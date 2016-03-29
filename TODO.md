# gen_rpc TODO

This is a list of pending features or code technical debt for `gen_rpc`:

- Implement SSL connectivity, including CN-based authentication
- Implement per-id-and-node tuple connection sharing to spread workload on multiple mailboxes per node
- Implement static port range allocation (instead of listening to 0) to adhere to potential corporate firewall rules