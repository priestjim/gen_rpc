basho_bench_gen_rpc
=====

Bechmarking for gen_rpc. 

Build
-----
* create benchtest tool for benchmarking
    $ make benchtest
* read the test config under priv directory
* ./start_target.sh starts gen_rpc server where requests be sent to
* ./start_test.sh calls basho_bench to load and execute the test in test_driver
* Check the test config file and scripts for default nodenames and erlang cookie.They needto match.

TODO
-----
* test script only contains gen_rpc:call and gen_rpc:cast. They don't cover all the api
* test config is just samples.


