# gen_rpc

[![Build Status](https://travis-ci.org/priestjim/gen_rpc.svg)](https://travis-ci.org/priestjim/gen_rpc) 
master: [![Coverage Status](https://coveralls.io/repos/priestjim/gen_rpc/badge.svg?branch=master&service=github)](https://coveralls.io/github/linearregression/gen_rpc?branch=master)
develop: [![Coverage Status](https://coveralls.io/repos/priestjim/gen_rpc/badge.svg?branch=develop&service=github)](https://coveralls.io/github/linearregression/gen_rpc?branch=develop)


An Erlang RPC library for out-of-band messaging

It is a library designed to solve when the amount of messages exchanged between erlang nodes overwhelm all out-of-the-box solutions (such as rpc/rex and remote spawn) Erlang offers and the stability of your infrastructure is threatened.

