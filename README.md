# gen_rpc: A scalable RPC library for Erlang-VM based languages.

## Overview

- Latest release: ![Tag Version](https://img.shields.io/github/tag/priestjim/gen_rpc.svg)
- Branch status (`master`): [![Build Status](https://travis-ci.org/priestjim/gen_rpc.svg?branch=master)](https://travis-ci.org/priestjim/gen_rpc) [![Coverage Status](https://coveralls.io/repos/priestjim/gen_rpc/badge.svg?branch=master&service=github)](https://coveralls.io/github/priestjim/gen_rpc?branch=master)
- Branch status (`develop`): [![Build Status](https://travis-ci.org/priestjim/gen_rpc.svg?branch=develop)](https://travis-ci.org/priestjim/gen_rpc) [![Coverage Status](https://coveralls.io/repos/priestjim/gen_rpc/badge.svg?branch=develop&service=github)](https://coveralls.io/github/priestjim/gen_rpc?branch=develop)
- Issues: [![GitHub issues](https://img.shields.io/github/issues/priestjim/gen_rpc.svg)](https://github.com/priestjim/gen_rpc/issues)
- License: [![GitHub license](https://img.shields.io/badge/license-Apache%202-blue.svg)](https://raw.githubusercontent.com/priestjim/gen_rpc/master/LICENSE)

## Rationale

The reasons for developing `gen_rpc` became apparent after a lot of trial and error while trying to scale a distributed Erlang infrastructure using the `rpc` library initially and subsequently `erlang:spawn/4` (remote spawn). Both these solutions suffer from very specific issues under a sufficiently high number of requests.

The `rpc` library operates by shipping data over the wire via Distributed Erlang's ports into a registered `gen_server` on the other side called `rex` (Remote EXecution server), which is running as part of the standard distribution. In high traffic scenarios, this allows the inherent problem of running a single `gen_server` server to manifest: mailbox flooding. As the number of nodes participating in a data exchange with the node in question increases, so do the messages that `rex` has to deal with, eventually becoming too much for the process to handle (don't forget this is confined to a single thread).

Enter `erlang:spawn/4` (_remote spawn_ from now on). Remote spawn dynamically spawns processes on a remote node, skipping the single-mailbox restriction that `rex` has. The are various libraries written to leverage that loophole (such as [Rexi](https://github.com/cloudant/rexi)), however there's a catch.

Remote spawn was not designed to ship large amounts of data as part of the call's arguments. Hence, if you want to ship a large binary such as a picture or a transaction log (large can also be small if your network is slow) over remote spawn, sooner or later you'll see this message popping up in your logs if you have subscribed to the system monitor through `erlang:system_monitor/2`:

    {monitor,<4685.187.0>,busy_dist_port,#Port<4685.41652>}

This message essentially means that the VM's distributed port pair was busy while the VM was trying to use it for some other task like _Distributed Erlang heartbeat beacons_ or _mnesia synchronization_. This of course wrecks havoc in certain timing expectations these subsystems have and the results can be very problematic: the VM might detect a node as disconnected even though everything is perfectly healthy and `mnesia` might misdetect a network partition.

`gen_rpc` solves both these problems by sharding data coming from different nodes to different processes (hence different mailboxes) and by using different `gen_tcp` ports for different nodes (hence not utilizing the Distributed Erlang ports).

# Build Dependencies

To build this project you need to have the following:

* **Erlang/OTP** >= 17.0

* **git** >= 1.7

* **GNU make** >= 3.80

* **rebar3** >= 3.0-beta4

## Usage

Getting started with `gen_rpc` is easy. First, add the appropriate dependency line to your `rebar.config`:

    {deps, [
        {gen_rpc, {git, "https://github.com/priestjim/gen_rpc.git", {branch, "master"}}}
    ]}.

Then, add `gen_rpc` as a dependency application to your `.app.src`/`.app` file:

    {application, my_app, [
        {applications, [kernel, stdlib, gen_rpc]}
    ]}

Finally, start a couple of nodes to test it out:

    (my_app@127.0.0.1)1> gen_rpc:call('other_node@1.2.3.4', erlang, node, []).
    'other_node@1.2.3.4'

## Build Targets

`gen_rpc` bundles a `Makefile` that makes development straightforward.

To build `gen_rpc` simply run:

    make

To run the full test suite, run:

    make test

To run the full test suite, the XRef tool and Dialyzer, run:

    make dist

To build the project and drop in a console while developing, run:

    make shell

To clean every build artifact and log, run:

    make distclean

## API

`gen_rpc` implements only the subset of the functions of the `rpc` library that make sense for the problem it's trying to solve. The library's function interface and return values is **100%** compatible with `rpc` with only one addition: Error return values include `{badrpc, Error}` for RPC-based errors but also `{badtcp, Error}` for TCP-based errors.

For more information on what the functions below do, run `erl -man rpc`.

### Functions exported

- `call(Node, Module, Function, Args)` and `call(Node, Module, Function, Args, Timeout)`: A blocking synchronous call, in the `gen_server` fashion.

- `cast(Node, Module, Function, Args)`: A non-blocking fire-and-forget call.

- `async_call(Node, Module, Function, Args)`, `yield(Key)`, `nb_yield(Key)` and `nb_yield(Key, Timeout)`: Promise-based function pairs.

- `multicall(Module, Function, Args)`, `multicall(Nodes, Module, Function, Args)`, `multicall(Module, Function, Args, Timeout)` and `multicall(Nodes, Module, Function, Args, Timeout)`: Multi-node version of the `call` function.

- `eval_everywhere(Module, Function, Args)` and `eval_everywhere(Nodes, Module, Function, Args)`: Multi-node version of the `cast` function.

### Application settings

- `connect_timeout`: Default timeout for the initial node-to-node connection in **milliseconds**.

- `send_timeout`: Default timeout for the transmission of a request (`call`/`cast` etc.) from the local node to the remote node in **milliseconds**.

- `receive_timeout`: Default timeout for the reception of a response in a `call` in **milliseconds**.

- `client_inactivity_timeout`: Inactivity period in **milliseconds** after which a client connection to a node will be closed (and hence have the TCP file descriptor freed).

- `server_inactivity_timeout`: Inactivity period in **milliseconds** after which a server port will be closed (and hence have the TCP file descriptor freed).

- `async_call_inactivity_timeout`: Inactivity period in **milliseconds** after which a pending process holding an `async_call` return value will exit. This is used for process sanitation purposes so please make sure to set it in a sufficiently high number (or `infinity`).

## Architecture

TBD.

## Performance

`gen_rpc` is being used in production extensively with over **150.000 incoming calls/sec/node** on a **8-core Intel Xeon E5** CPU and **Erlang 18.2**. The median payload size is **500 KB**. No stability or scalability issues have been detected in over a year.

## Known Issues

- When shipping an anonymous function over to another node, it will fail to execute because of the way Erlang implements anonymous functions (Erlang serializes the function metadata but not the function body). This issue also exists in both `rpc` and remote spawn.

- Client connections are registered with the connected node's name. This might cause issues if you have other processes that register their names like that.

## Licensing

This project is published and distributed under the [Apache License](LICENSE).

## Contributing

Please see [CONTRIBUTING.md](CONTRIBUTING.md)

### Contributors:

- [Edward Tsang](https://github.com/linearregression)
