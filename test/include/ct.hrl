%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

%%% Common Test includes
-include_lib("common_test/include/ct.hrl").
%%% Include this library's name macro
-include_lib("gen_rpc/include/app.hrl").

%%% Node definitions
-define(NODE, 'gen_rpc_master@127.0.0.1').
-define(SLAVE, 'gen_rpc_slave@127.0.0.1').
-define(SLAVE1, 'gen_rpc_slave1@127.0.0.1').
-define(SLAVE2, 'gen_rpc_slave2@127.0.0.1').

-define(FAKE_NODE, 'fake_node@127.0.1.1').
