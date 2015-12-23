# Overview
An Erlang RPC library for out-of-band messaging.

[![Build Status](https://travis-ci.org/priestjim/gen_rpc.svg)](https://travis-ci.org/priestjim/gen_rpc)

This library is designed to scale RPC-call based infrastructures where regular remote spawn or `rpc`/`rex` calls fail to manage that.
It overcomes two basic shortcomings of the current implementation of the Erlang RPC framework:

- Single mailbox for incoming RPC calls

- VM heartbeat blocking for big arg remote spawns

# Contributors

- [https://github.com/linearregression](Edward Tsang)