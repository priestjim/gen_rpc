%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(multi_rpc_with_key_SUITE).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% CT Macros
-include_lib("test/include/ct.hrl").

%%% No need to export anything, everything is automatically exported
%%% as part of the test profile

%%% ===================================================
%%% CT callback functions
%%% ===================================================
all() ->
    gen_rpc_test_helper:get_test_functions(?MODULE).

init_per_suite(Config) ->
    %% Starting Distributed Erlang and the app on local node
    ok = gen_rpc_test_helper:start_distributed_master(tcp),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(sbcast_with_bad_server, Config) ->
    ok = gen_rpc_test_helper:restart_application(),
    ok = gen_rpc_test_helper:start_master(tcp),
    ok = gen_rpc_test_helper:start_slave(tcp),
    %% Set a low sbcast timeout
    ok = rpc:call(?SLAVE, application, set_env, [?APP, sbcast_receive_timeout, 500]),
    Config;

init_per_testcase(_OtherTest, Config) ->
    ok = gen_rpc_test_helper:restart_application(),
    ok = gen_rpc_test_helper:start_master(tcp),
    ok = gen_rpc_test_helper:start_slave(tcp),
    Config.

end_per_testcase(_OtherTest, Config) ->
    ok = gen_rpc_test_helper:stop_slave(),
    Config.

%%% ===================================================
%%% Test cases
%%% ===================================================
eval_everywhere_mfa_multiple_nodes(_Config) ->
    ConnectedNodes = [{?SLAVE,key1}, ?SLAVE],
    Msg = Name = 'evalmfamulti',
    TestPid = self(),
    ok = gen_rpc_test_helper:terminate_process(Name),
    Pid = gen_rpc_test_helper:spawn_listener2(?SLAVE, ?SLAVE, Name, TestPid, 2),
    true = register(Name, Pid),
    abcast = gen_rpc:eval_everywhere(ConnectedNodes, 'gen_rpc_test_helper', ping, [{?MASTER, Name, Msg}]),
    {ok, passed} = gen_rpc_test_helper:wait_for_reply(?SLAVE, ?SLAVE),
    ok.

multicall_multiple_nodes(_Config) ->
    ConnectedNodes = [{?SLAVE,random_key}, ?SLAVE],
    {[{_,_,_}, {_,_,_}], []} = gen_rpc:multicall(ConnectedNodes, os, timestamp, []),
    [?SLAVE] = gen_rpc:nodes(),
    [_WithKey, _Bare] = supervisor:which_children(gen_rpc_client_sup).

multicall_multiple_nodes_and_local(_Config) ->
    ConnectedNodes = [{?SLAVE,random_key}, ?SLAVE],
    {[{_,_,_}, {_,_,_}], []} = gen_rpc:multicall(ConnectedNodes, os, timestamp, []),
    {[{_,_,_}, {_,_,_}], []} = gen_rpc:multicall(os, timestamp, []),
    [?SLAVE] = gen_rpc:nodes(),
    [_WithKey, _Bare, _Local] = supervisor:which_children(gen_rpc_client_sup).

multicall_multiple_nodes_with_timeout(_Config) ->
    ConnectedNodes = [{?SLAVE,random_key}, ?SLAVE],
    {[{_,_,_}, {_,_,_}], []} = gen_rpc:multicall(ConnectedNodes, os, timestamp, [], 5000),
    [?SLAVE] = gen_rpc:nodes(),
    {[], BadNodes} = gen_rpc:multicall(ConnectedNodes, timer, sleep, [500], 100),
    true = lists:member(?SLAVE, BadNodes).

abcast(_Config) ->
    true = erlang:register(test_process_123, self()),
    abcast = rpc:call(?SLAVE, gen_rpc, abcast, [[{?MASTER,random_key}], test_process_123, this_is_a_test]),
    receive
        this_is_a_test -> ok;
        _ -> erlang:error(invalid_message)
    after
        2000 -> erlang:error(timeout)
    end,
    [?MASTER] = rpc:call(?SLAVE, gen_rpc, nodes, []),
    abcast = rpc:call(?SLAVE, gen_rpc, abcast, [test_process_123, this_is_a_test]),
    receive
        this_is_a_test -> ok;
        _ -> erlang:error(invalid_message)
    after
        2000 -> erlang:error(timeout)
    end,
    true = erlang:unregister(test_process_123).

abcast_with_bad_server(_Config) ->
    true = erlang:register(test_process_123, self()),
    abcast = rpc:call(?SLAVE, gen_rpc, abcast, [[{?MASTER,random_key}, ?FAKE_NODE], test_process_123, this_is_a_test]),
    receive
        this_is_a_test -> ok;
        _ -> erlang:error(invalid_message)
    after
        2000 -> erlang:error(timeout)
    end,
    true = erlang:unregister(test_process_123).

sbcast(_Config) ->
    true = erlang:register(test_process_123, self()),
    {[{?MASTER,random_key}], []} = rpc:call(?SLAVE, gen_rpc, sbcast, [[{?MASTER,random_key}], test_process_123, this_is_a_test]),
    receive
        this_is_a_test -> ok;
        _ -> erlang:error(invalid_message)
    after
        2000 -> erlang:error(timeout)
    end,
    [?MASTER] = rpc:call(?SLAVE, gen_rpc, nodes, []),
    {[?MASTER], [?SLAVE]} = rpc:call(?SLAVE, gen_rpc, sbcast, [test_process_123, this_is_a_test]),
    receive
        this_is_a_test -> ok;
        _ -> erlang:error(invalid_message)
    after
        2000 -> erlang:error(timeout)
    end,
    true = erlang:unregister(test_process_123).

sbcast_with_bad_server(_Config) ->
    true = erlang:register(test_process_123, self()),
    {[{?MASTER,random_key}], [?FAKE_NODE]} = rpc:call(?SLAVE, gen_rpc, sbcast, [[{?MASTER,random_key}, ?FAKE_NODE],
                                                      test_process_123, this_is_a_test]),
    receive
        this_is_a_test -> ok;
        _ -> erlang:error(invalid_message)
    after
        2000 -> erlang:error(timeout)
    end,
    true = erlang:unregister(test_process_123).
