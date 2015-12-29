%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(multi_rpc_functional_SUITE).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% CT Macros
-include_lib("test/include/ct.hrl").

%%% No need to export anything, everything is automatically exported
%%% as part of the test profile

-define(TESTSRV, test_app_server).

%%% ===================================================
%%% CT callback functions
%%% ===================================================
all() ->
    gen_rpc_test_helper:get_test_functions(?MODULE).

init_per_suite(Config) ->
    %% Starting Distributed Erlang on local node
    {ok, _Pid} = gen_rpc_test_helper:start_distribution(?NODE),
    %% Setup application logging
    ok = gen_rpc_test_helper:set_application_environment(),
    %% Starting the application locally
    {ok, _MasterApps} = application:ensure_all_started(?APP),
    ok = ct:pal("Started [remote_functional] suite with master node [~s]", [node()]),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(client_inactivity_timeout, Config) ->
    ok = start_slaves(),
    ok = gen_rpc_test_helper:restart_application(),
    ok = application:set_env(?APP, client_inactivity_timeout, infinity),
    Config;

init_per_testcase(server_inactivity_timeout, Config) ->
    ok = start_slaves(),
    ok = gen_rpc_test_helper:restart_application(),
    ok = application:set_env(?APP, server_inactivity_timeout, infinity),
    Config;

init_per_testcase(_OtherTest, Config) ->
    ok = start_slaves(),
    Config.

end_per_testcase(client_inactivity_timeout, Config) ->
    ok = stop_slaves(),
    ok = gen_rpc_test_helper:restart_application(),
    Config;

end_per_testcase(server_inactivity_timeout, Config) ->
    ok = stop_slaves(),
    ok = gen_rpc_test_helper:restart_application(),
    Config;

end_per_testcase(_OtherTest, Config) ->
    ok = stop_slaves(),
    Config.

%%% ===================================================
%%% Test cases
%%% ===================================================
%% Test main functions
multi_call(_Config) ->
    ok = ct:pal("Testing [multi_call]"),
    [[?SLAVE1,?SLAVE2], []] = gen_rpc:multicall([?SLAVE1, ?SLAVE2], erlang, node, 5000, 100).

multi_call_timeout(_Config) ->
    ok = ct:pal("Testing [multi_call_timeout]"),
    [[], [?SLAVE1]] = gen_rpc:multicall([?SLAVE1], timer, sleep, [10000], 1, 1).

multi_call_mfa_undef(_Config) ->
    ok = ct:pal("Testing [multi_call_mfa_undef]"),
    [[], [?SLAVE1,?SLAVE2]] = gen_rpc:multicall([?SLAVE1, ?SLAVE2], erlang, undef, ['die'], 5000, 100).

multi_call_mfa_exit(_Config) ->
    ok = ct:pal("Testing [multi_call_mfa_exit]"),
    [[], [?SLAVE1,?SLAVE2]] = gen_rpc:multicall([?SLAVE1, ?SLAVE2], erlang, exit, ['die'], 5000, 100).

multi_call_mfa_throw(_Config) ->
    ok = ct:pal("Testing [multi_call_mfa_throw]"),
    [['throwXdown', 'throwXdown'], []] = gen_rpc:multicall([?SLAVE1, ?SLAVE2], erlang, throw, ['throwXdown'], 5000, 100).

multi_call_inexistent_node(_Config) ->
    ok = ct:pal("Testing [multi_call_inexistent_node]"),
    [[], [?FAKE_NODE]] = gen_rpc:multicall([?FAKE_NODE], os, timestamp, 10, 10).

multi_call_no_node(_Config) ->
    ok = ct:pal("Testing [multi_call_no_node]"),
    [[],[]] = gen_rpc:multicall([], os, timestamp, 10, 10).

multi_call_multiple_nodes_fail_end(_Config) ->
    ok = ct:pal("Testing [multi_call_multiple_nodes]"),
    ok = ct:pal("Case 1: Failed node at end of list"),
    [[_,_],[?FAKE_NODE]] = gen_rpc:multicall([?SLAVE1, ?SLAVE2, ?FAKE_NODE], os, timestamp, 5000, 100).

multi_call_multiple_nodes_fail_middle(_Config) ->
    ok = ct:pal("Testing [multi_call_multiple_nodes]"),
    ok = ct:pal("Case 2: Failed node at end of list"),
    [[_,_],[?FAKE_NODE]] = gen_rpc:multicall([?SLAVE1, ?FAKE_NODE, ?SLAVE2], os, timestamp, 5000, 100).

multi_call_multiple_nodes_fail_start(_Config) ->
    ok = ct:pal("Testing [multi_call_multiple_nodes]"),
    ok = ct:pal("Case 3: Failed node at start of list"),
    [[_,_],[?FAKE_NODE]] = gen_rpc:multicall([?FAKE_NODE, ?SLAVE1, ?SLAVE2], os, timestamp, 5000, 100).


%%% ===================================================
%%% Auxiliary functions for test cases
%%% ===================================================
start_slaves() ->
    ok = gen_rpc_test_helper:start_slave(?SLAVE1),
    ok = gen_rpc_test_helper:start_slave(?SLAVE2),
    ok = ct:pal("Slaves started"),
    ok.

stop_slaves() ->
    ok = gen_rpc_test_helper:stop_slave(?SLAVE1),
    ok = gen_rpc_test_helper:stop_slave(?SLAVE2),
    ok = ct:pal("Slaves stopped").
