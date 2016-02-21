# Overview
An Erlang RPC library for out-of-band messaging.

![Tag Version](https://img.shields.io/github/tag/priestjim/gen_rpc.svg)
[![Build Status](https://travis-ci.org/priestjim/gen_rpc.svg?branch=master)](https://travis-ci.org/priestjim/gen_rpc) [![Build Status](https://travis-ci.org/priestjim/gen_rpc.svg?branch=develop)](https://travis-ci.org/priestjim/gen_rpc) [![Coverage Status](https://coveralls.io/repos/priestjim/gen_rpc/badge.svg?branch=develop&service=github)](https://coveralls.io/github/priestjim/gen_rpc?branch=develop) [![Coverage Status](https://coveralls.io/repos/priestjim/gen_rpc/badge.svg?branch=master&service=github)](https://coveralls.io/github/priestjim/gen_rpc?branch=master)
[![GitHub issues](https://img.shields.io/github/issues/priestjim/gen_rpc.svg)](https://github.com/priestjim/gen_rpc/issues)
[![GitHub license](https://img.shields.io/badge/license-Apache%202-blue.svg)](https://raw.githubusercontent.com/priestjim/gen_rpc/master/LICENSE)

This library is designed to scale RPC-call based infrastructures where regular remote spawn or `rpc`/`rex` calls fail to manage that.
It overcomes two basic shortcomings of the current implementation of the Erlang RPC framework:

- Single mailbox for incoming RPC calls

- VM heartbeat blocking for big arg remote spawns

# Contributors

- [Edward Tsang](https://github.com/linearregression)
