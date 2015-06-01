%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos, Inc. All Rights Reserved.
%%%

-module(functional_SUITE).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% CT Macros
-include_lib("gen_rpc/include/ct.hrl").

%%% Node definitions
-define(MASTER, 'gen_rpc_master@127.0.0.1').
-define(SLAVE, 'gen_rpc_slave@127.0.0.1').
-define(SLAVE_IP, '127.0.0.1').
-define(SLAVE_NAME, 'gen_rpc_slave').

%%% Common Test callbacks
-export([all/0, init_per_suite/1, end_per_suite/1]).
%%% Testing functions
-export([supervisor_black_box/1, call/1, cast/1, send_timeout/1]).

%%% ===================================================
%%% CT callback functions
%%% ===================================================
all() -> [supervisor_black_box, call, cast, send_timeout].

%% TODO: Combine master to slave and slave to master
%% in groups so we can test full duplex communication
%% to and fro a binary pair of nodes

init_per_suite(Config) ->
    %% Starting Distributed Erlang on local node
    {ok, _Pid} = net_kernel:start([?MASTER, longnames]),
    %% Starting the application locally
    {ok, _MasterApps} = application:ensure_all_started(gen_rpc),
    %% Setup application logging
    ?ctApplicationSetup(),
    ct:pal("Started [functional] suite with master node [~s]", [node()]),
    Config.

end_per_suite(_Config) ->
    ok.

%%% ===================================================
%%% Test cases
%%% ===================================================
%% Test supervisor's status
supervisor_black_box(_Config) ->
    true = erlang:is_process_alive(whereis(gen_rpc_receiver_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_acceptor_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_sender_sup)),
    ok.

call(_Config) ->
    {_Mega, _Sec, _Micro} = gen_rpc:call(?MASTER, os, timestamp).

cast(_Config) ->
    ok = gen_rpc:cast(?MASTER, os, timestamp).

send_timeout(_Config) ->
    {badtcp, receive_timeout} = gen_rpc:call(?MASTER, timer, sleep, [6000]).
