%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(functional_SUITE).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% CT Macros
-include_lib("gen_rpc/include/ct.hrl").

%%% Node definitions
-define(NODE, 'gen_rpc_master@127.0.0.1').

%%% Common Test callbacks
-export([all/0, init_per_suite/1, end_per_suite/1]).
%%% Testing functions
-export([supervisor_black_box/1, call/1, call_with_receive_timeout/1, cast/1, receive_stale_data/1]).

%%% ===================================================
%%% CT callback functions
%%% ===================================================
all() ->
    {exports, Functions} = lists:keyfind(exports, 1, ?MODULE:module_info()),
    [FName || {FName, _} <- lists:filter(
                               fun ({module_info,_}) -> false;
                                   ({all,_}) -> false;
                                   ({init_per_suite,1}) -> false;
                                   ({end_per_suite,1}) -> false;
                                   ({_,1}) -> true;
                                   ({_,_}) -> false
                               end, Functions)].

init_per_suite(Config) ->
    %% Starting Distributed Erlang on local node
    {ok, _Pid} = net_kernel:start([?NODE, longnames]),
    %% Starting the application locally
    {ok, _MasterApps} = application:ensure_all_started(gen_rpc),
    %% Setup application logging
    ?ctApplicationSetup(),
    ok = ct:pal("Started [functional] suite with master node [~s]", [node()]),
    Config.

end_per_suite(_Config) ->
    ok.

%%% ===================================================
%%% Test cases
%%% ===================================================
%% Test supervisor's status
supervisor_black_box(_Config) ->
    ok = ct:pal("Testing [supervisor_black_box]"),
    true = erlang:is_process_alive(whereis(gen_rpc_receiver_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_acceptor_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_sender_sup)),
    ok.

%% Test main functions
call(_Config) ->
    ok = ct:pal("Testing [call]"),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?NODE, os, timestamp).

call_with_receive_timeout(_Config) ->
    ok = ct:pal("Testing [call_with_receive_timeout]"),
    {badtcp, receive_timeout} = gen_rpc:call(?NODE, timer, sleep, [500], 1),
    ok = timer:sleep(500).

cast(_Config) ->
    ct:pal("Testing [cast]"),
    ok = gen_rpc:cast(?NODE, os, timestamp).

receive_stale_data(_Config) ->
    ok = ct:pal("Testing [receive_stale_data]"),
    %% Step 1: Send data with a lengthy execution time
    {badtcp, receive_timeout} = gen_rpc:call(?NODE, timer, sleep, [1000], 500),
    %% Step 2: Send more data with a lengthy execution time
    {badtcp, receive_timeout} = gen_rpc:call(?NODE, timer, sleep, [1000], 500),
    %% Step 3: Send a quick function
    {_Mega, _Sec, _Micro} = gen_rpc:call(?NODE, os, timestamp).
