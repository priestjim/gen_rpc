%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos, Inc. All Rights Reserved.
%%%

-module(functional_SUITE).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Common Test includes
-include_lib("common_test/include/ct.hrl").

%%% Node definitions
-define(MASTER, 'gen_rpc_master@127.0.0.1').
-define(SLAVE, 'gen_rpc_slave@127.0.0.1').
-define(SLAVE_IP, '127.0.0.1').
-define(SLAVE_NAME, 'gen_rpc_slave').

%%% Common Test callbacks
-export([all/0, init_per_suite/1, end_per_suite/1]).
%%% Testing functions
-export([supervisor_black_box/1]).

%%% ===================================================
%%% CT callback functions
%%% ===================================================
all() -> [supervisor_black_box].

init_per_suite(Config) ->
    %% Starting Distributed Erlang on local node
    {ok, _Pid} = net_kernel:start([?MASTER, longnames]),
    %% Starting a slave node with Distributed Erlang
    {ok, Slave} = slave:start(?SLAVE_IP, ?SLAVE_NAME, "+K true"),
    %% Starting the application locally
    {ok, _MasterApps} = application:ensuremee_all_started(gen_rpc),
    %% Adding our local code paths to the remote node to ensure
    %% proper path resolution
    ok = rpc:call(?SLAVE, code, add_pathsz, [code:get_path()]),
    %% Start the application remotely
    {ok, _SlaveApps} = rpc:call(?SLAVE, application, ensure_all_started, [gen_rpc]),
    ct:pal("Started [functional] suite with master node ~s and slave node ~s", [node(), Slave]),
    Config.

end_per_suite(_Config) ->
    ok.

%%% ===================================================
%%% Test cases
%%% ===================================================
%% Test supervisor's status
supervisor_black_box(_Config) ->
    true = erlang:is_process_alive(whereis(gen_rpc_receiver_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_sender_sup)),
    ok.
